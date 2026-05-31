// ContentView.swift


import SwiftUI

struct ContentView: View {
    
    @StateObject private var manager = SpeechMatcherManager()
    
    var body: some View {
        VStack(spacing: 32) {
            
            // MARK: - 단어 매칭 상태 표시
            HStack(spacing: 12) {
                ForEach(Array(manager.targetWords.enumerated()), id: \.offset) { index, word in
                    Text(word)
                        .font(.title2.bold())
                        .foregroundColor(index <= manager.currentIndex ? .green : .gray)
                }
            }
            
            // MARK: - 실시간 인식 텍스트
            VStack(alignment: .leading, spacing: 8) {
                Text("인식된 텍스트")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(manager.recognizedText.isEmpty ? "…" : manager.recognizedText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            // MARK: - 현재 매칭 인덱스
            Text("currentIndex: \(manager.currentIndex)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // MARK: - 에러 메시지
            if let error = manager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // MARK: - 녹음 제어 버튼
            Button(action: {
                if manager.isRecording {
                    manager.stopRecording()
                } else {
                    manager.startRecording()
                }
            }) {
                Text(manager.isRecording ? "녹음 종료" : "녹음 시작")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(manager.isRecording ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
