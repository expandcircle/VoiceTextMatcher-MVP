    // SpeechMatcherManager.swift
    // 필요한 Info.plist 권한:
    // - NSMicrophoneUsageDescription: 마이크 사용 권한
    // - NSSpeechRecognitionUsageDescription: 음성 인식 사용 권한

    import Foundation
    import AVFoundation
    import Speech
    import Combine

    @MainActor
    class SpeechMatcherManager: ObservableObject {
        
        // MARK: - Published Properties
        @Published var recognizedText: String = ""
        @Published var currentIndex: Int = -1           //currentIndex = 한 문장 내 띄어쓰기 단위로 구분
        @Published var currentStageIndex: Int = 0       //currentStageIndex = 여러 문장 단계로 구분
        @Published var isRecording: Bool = false
        @Published var errorMessage: String? = nil
        
        // MARK: - Target Words
        let targetStages: [[String]] = [
            //1단계
            ["산토끼", "토끼야", "어디를", "가느냐"],
            //2단계
            ["나비야", "나비야", "이리", "날아오너라"],
            //3단계
            ["떴다", "떴다", "비행기", "날아라", "날아라"],
            //4단계
            ["곰세마리가", "한집에있어", "아빠곰", "엄마곰", "애기곰"]
        ]
        
        // MARK: - Private Properties
        private var audioEngine = AVAudioEngine()
        private var speechRecognizer: SFSpeechRecognizer?
        private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
        private var recognitionTask: SFSpeechRecognitionTask?
        
        // MARK: - Init
        init() {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
        }
        
        // MARK: - Public Methods
        
        /// 권한 확인 후 녹음 시작
        func startRecording() {
            requestPermissions { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    Task { @MainActor in
                        do {
                            try self.startSpeechRecognition()
                        } catch {
                            self.errorMessage = "음성 인식 시작 실패: \(error.localizedDescription)"
                        }
                    }
                } else {
                    Task { @MainActor in
                        self.errorMessage = "마이크 또는 음성 인식 권한이 없습니다."
                    }
                }
            }
        }
        
        /// 녹음 종료
        func stopRecording() {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            recognitionRequest = nil
            recognitionTask = nil
            isRecording = false
        }
        
        // MARK: - Matching Logic
        
        /// 인식된 텍스트와 targetWords를 앞에서부터 순서대로 매칭
        /// 띄어쓰기 오류를 허용하기 위해 공백 제거 후 비교 :: 산 토끼 = 산토끼
        func checkMatching(recognizedText: String) -> Int {
            // 공백 제거한 인식 텍스트
            let cleanedRecognized = recognizedText
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\n", with: "")
            
            let currentStageWords = targetStages[currentStageIndex]
            
            // targetWords를 순서대로 붙여서 누적 매칭
            var cumulativeTarget = ""
            var matchedIndex = -1
            
            for (index, word) in currentStageWords.enumerated() {
                // 공백 제거한 단어
                let cleanedWord = word.replacingOccurrences(of: " ", with: "")
                cumulativeTarget += cleanedWord
                
                // 인식 텍스트가 누적 타겟 문자열을 포함하는지 확인
                if cleanedRecognized.contains(cumulativeTarget) {
                    matchedIndex = index
                } else {
                    // 순서가 깨지면 더 이상 확인하지 않음
                    break
                }
            }
            
            return matchedIndex
        }
        
        // MARK: - Private Methods
        
        private func requestPermissions(completion: @escaping (Bool) -> Void) {
            SFSpeechRecognizer.requestAuthorization { authStatus in
                guard authStatus == .authorized else {
                    completion(false)
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    completion(granted)
                }
            }
        }
        
        private func startSpeechRecognition() throws {
            // 이전 세션 정리
            stopRecording()
            
            // 인식기 확인
            guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
                throw SpeechError.recognizerUnavailable
            }
            
            // 오디오 세션 설정
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // 인식 요청 생성
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                throw SpeechError.requestCreationFailed
            }
            
            // 부분 결과(실시간) 활성화
            recognitionRequest.shouldReportPartialResults = true
            
            // 인식 태스크 시작
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    Task { @MainActor in
                        self.recognizedText = text
                        let newIndex = self.checkMatching(recognizedText: text)
                        // currentIndex는 단방향 증가 (뒤로 돌아가지 않음)
                        if newIndex > self.currentIndex {
                            self.currentIndex = newIndex
                        }
                    }
                }
                
                if let error = error {
                    Task { @MainActor in
                        self.errorMessage = "인식 오류: \(error.localizedDescription)"
                        self.stopRecording()
                    }
                }
                
                if result?.isFinal == true {
                    Task { @MainActor in
                        self.stopRecording()
                    }
                }
            }
            
            // 오디오 탭 설정
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
            
            // 오디오 엔진 시작
            audioEngine.prepare()
            try audioEngine.start()
            
            // 상태 초기화
            recognizedText = ""
            currentIndex = -1
            errorMessage = nil
            isRecording = true
        }
        
        // MARK: - Error Types
        
        enum SpeechError: Error, LocalizedError {
            case recognizerUnavailable
            case requestCreationFailed
            
            var errorDescription: String? {
                switch self {
                case .recognizerUnavailable: return "음성 인식기를 사용할 수 없습니다."
                case .requestCreationFailed: return "인식 요청 생성에 실패했습니다."
                }
            }
        }
    }

