import Foundation
import Combine
import AVFoundation

enum SessionState: String {
    case idle = "Ocioso"
    case listening = "Ouvindo..."
    case processing = "Processando..."
    case speaking = "Hermes Falando..."
}

class VoiceSession: ObservableObject {
    static let shared = VoiceSession()
    
    @Published var sessionState: SessionState = .idle
    @Published var connectionState: HermesConnectionState = .disconnected
    @Published var isCallActive: Bool = false
    @Published var isMuted: Bool = false
    @Published var errorMessage: String? = nil
    @Published var currentTranscript: String = ""
    @Published var connectionLog: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    private var accumulatedResponse = ""
    
    private init() {
        // Sincroniza o status de conexão com a UI
        HermesAgentClient.shared.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
            }
            .store(in: &cancellables)
        
        // Sincroniza os logs de conexão com a UI
        HermesAgentClient.shared.lastConnectionLogPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] log in
                self?.connectionLog = log
            }
            .store(in: &cancellables)
        
        // Define as dependências cruzadas
        CallManager.shared.delegate = self
        AudioEngineManager.shared.delegate = self
        SpeechRecognizer.shared.delegate = self
        SpeechSynthesizer.shared.delegate = self
    }
    
    // MARK: - Ações Públicas
    func startCall() {
        CallManager.shared.startCall()
    }
    
    func endCall() {
        CallManager.shared.endCall()
    }
    
    func toggleMute() {
        CallManager.shared.setMuted(!isMuted)
    }
    
    // MARK: - Ciclo de Vida da Ligação
    private func startAudioAndAgent() {
        let settings = SettingsStore.shared
        
        DispatchQueue.main.async {
            self.isCallActive = true
            self.errorMessage = nil
            self.currentTranscript = ""
        }
        
        SpeechRecognizer.shared.configure(localeIdentifier: settings.sttLanguage)
        SpeechSynthesizer.shared.configureVoice(locale: settings.sttLanguage)
        
        // Solicita autorização de microfone e transcrição
        SpeechRecognizer.requestPermissions { [weak self] granted in
            guard let self = self else { return }
            
            guard granted else {
                print("Permissões de áudio/STT recusadas pelo usuário.")
                DispatchQueue.main.async {
                    self.errorMessage = "Permissão de microfone ou reconhecimento de fala negada."
                }
                self.endCall()
                return
            }
            
            // Conecta ao WebSocket do Hermes
            Task {
                do {
                    try await HermesAgentClient.shared.connect()
                } catch {
                    print("Erro ao tentar conectar ao WebSocket: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.errorMessage = "Erro de conexão: \(error.localizedDescription)"
                    }
                }
            }
            
            // Ativa gravação de áudio e inicializa o reconhecimento de fala
            do {
                try AudioEngineManager.shared.start()
                try SpeechRecognizer.shared.startRecording()
                
                DispatchQueue.main.async {
                    self.sessionState = .listening
                }
            } catch {
                print("Erro ao iniciar AVAudioEngine ou SpeechRecognizer: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Erro ao iniciar o motor de áudio: \(error.localizedDescription)"
                }
                self.endCall()
            }
        }
    }
    
    private func stopAudioAndAgent() {
        AudioEngineManager.shared.stop()
        SpeechRecognizer.shared.stopRecording()
        SpeechSynthesizer.shared.stop()
        
        Task {
            await HermesAgentClient.shared.disconnect()
        }
        
        DispatchQueue.main.async {
            self.sessionState = .idle
            self.isCallActive = false
            self.isMuted = false
            self.currentTranscript = ""
        }
    }
}

// MARK: - CallManagerDelegate
extension VoiceSession: CallManagerDelegate {
    func callManagerDidActivateAudio() {
        startAudioAndAgent()
    }
    
    func callManagerDidDeactivateAudio() {
        stopAudioAndAgent()
    }
    
    func callManagerDidEndCall() {
        stopAudioAndAgent()
    }
    
    func callManagerDidFail(withError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "Falha no CallKit: \(error.localizedDescription)"
            self.isCallActive = false
            self.sessionState = .idle
        }
    }
    
    func callManagerDidMute(_ muted: Bool) {
        DispatchQueue.main.async {
            self.isMuted = muted
        }
        if muted {
            SpeechRecognizer.shared.stopRecording()
        } else {
            // Se voltarmos do mute e estivermos em modo de escuta, reativa gravação
            if sessionState == .listening {
                try? SpeechRecognizer.shared.startRecording()
            }
        }
    }
}

// MARK: - AudioEngineManagerDelegate
extension VoiceSession: AudioEngineManagerDelegate {
    func audioEngineDidReceiveBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Encaminha buffers de áudio do tap para o STT apenas quando estamos escutando o usuário e sem mute
        if sessionState == .listening && !isMuted {
            SpeechRecognizer.shared.appendAudioBuffer(buffer)
        }
    }
}

// MARK: - SpeechRecognizerDelegate
extension VoiceSession: SpeechRecognizerDelegate {
    func speechRecognizerDidRecognizeText(_ text: String) {
        print("Reconhecido parcial: \(text)")
        DispatchQueue.main.async {
            self.currentTranscript = text
        }
    }
    
    func speechRecognizerDidDetectSilence(withText text: String) {
        print("Silêncio detectado. Enviando texto final: \(text)")
        
        DispatchQueue.main.async {
            self.sessionState = .processing
            self.currentTranscript = text
        }
        
        // Pausa reconhecimento para evitar eco e capturar resposta
        SpeechRecognizer.shared.stopRecording()
        
        Task {
            do {
                accumulatedResponse = ""
                // Pede a resposta em streaming pelo WebSocket
                let stream = HermesAgentClient.shared.send(text)
                
                for try await chunk in stream {
                    accumulatedResponse += chunk
                }
                
                let textToSpeak = accumulatedResponse
                
                DispatchQueue.main.async {
                    if !textToSpeak.isEmpty {
                        self.sessionState = .speaking
                        SpeechSynthesizer.shared.speak(textToSpeak, rate: SettingsStore.shared.ttsRate)
                    } else {
                        // Resposta nula ou vazia: retorna ao estado de escuta
                        self.sessionState = .listening
                        try? SpeechRecognizer.shared.startRecording()
                    }
                }
            } catch {
                print("Erro ao enviar ou receber do Hermes: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.sessionState = .listening
                    try? SpeechRecognizer.shared.startRecording()
                }
            }
        }
    }
}

// MARK: - SpeechSynthesizerDelegate
extension VoiceSession: SpeechSynthesizerDelegate {
    func speechSynthesizerDidStartSpeaking() {
        DispatchQueue.main.async {
            self.sessionState = .speaking
            self.currentTranscript = ""
        }
        SpeechRecognizer.shared.stopRecording()
    }
    
    func speechSynthesizerDidFinishSpeaking() {
        DispatchQueue.main.async {
            self.sessionState = .listening
        }
        // Retorna a ouvir o microfone após o término da fala do Hermes, caso não esteja mutado
        if !isMuted {
            try? SpeechRecognizer.shared.startRecording()
        }
    }
}
