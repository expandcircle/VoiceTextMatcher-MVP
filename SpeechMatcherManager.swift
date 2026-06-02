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
    @Published var isPlaying: Bool = false
    
    // MARK: - Target Words
    let targetStages: [[String]] = [
        //1단계
        ["안녕", "하세요"],
        //2단계
        ["만나서", "반가워요"],
        //3단계
       // ["안녕", "하세요"],
        //4단계
       // ["만나서", "반가워요"]
    ]
    
    // MARK: - Private Properties
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var recordingURLs: [Int: URL] = [:]
    private var audioPlayer: AVAudioPlayer?
    
    
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
        
        if let audioFile = audioFile {
            recordingURLs[currentStageIndex] = audioFile.url
            print("저장완료: \(audioFile.url.lastPathComponent)")
        }
        audioFile = nil
        
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
    // MARK: - Stage control
    /// 현재 단계의 모든 단어를 매칭했는가
    var isCurrentStageComplete: Bool {
        currentIndex == targetStages[currentStageIndex].count - 1
    }
        
    var isLastStage: Bool {
        currentStageIndex == targetStages.count - 1
    }
    
    func goToNextStage() {
        guard !isLastStage else { return }
        if isRecording { stopRecording() }
        currentStageIndex += 1
        currentIndex = -1
        recognizedText = ""
        errorMessage = nil
    }
        
    
    //MARK: - Playback (다시듣기)
    /// 특정 단계 녹음 존재 여부 확인
    func hasRecording(for stageIndex: Int) -> Bool {
        return recordingURLs[stageIndex] != nil
    }
    
    /// 특정 단계 녹음 파일 재생
    func playRecording(for stageIndex: Int) {
        guard let url = recordingURLs[stageIndex] else {
            errorMessage = "\(stageIndex + 1) 단계 의 녹음 파일이 없습니다."
            return
        }
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            isPlaying = true
            print("재생 중: \(url.lastPathComponent)")
        } catch {
            errorMessage = "재생실패: \(error.localizedDescription)"
        }
    }
    
    /// 재생 중지
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    /// 현재 단계 녹음 다시 듣기
    func playCurrentRecording() {
        playRecording(for: currentStageIndex)
    }
    
    /// 모든 녹음 파일 URL 반환 (ML에 넘기기용)
    func allRecordingURLs() -> [Int : URL] {
        return recordingURLs
    }
    
    /// 녹음 파일 전체 삭제
    func clearAllRecordings() {
        for (_, url) in recordingURLs {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURLs.removeAll()
        print("모든 녹음 파일 삭제 완료")
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
         
            
            // 녹음 파일 생성
            let url = recordingURL(for: currentStageIndex)
            let settings: [String:Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            audioFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            
            //installTap
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
                try? self.audioFile?.write(from: buffer)
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
        private func recordingURL(for stageIndex: Int) -> URL {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask) [0]
            return docs.appendingPathComponent("stage_\(stageIndex).m4a")
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

