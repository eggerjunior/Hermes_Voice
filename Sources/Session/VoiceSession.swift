import Foundation
import Combine
import AVFoundation

enum SessionState: String {
    case idle = "Ocioso"
    case listening = "Ouvindo..."
    case processing = "Processando..."
    case speaking = "Hermes Falando..."
}

// @unchecked Sendable: singleton com acesso concorrente controlado (estado de UI na
// main thread; buffers de áudio na thread de áudio). Silencia os avisos de captura de
// `self` em closures @Sendable (Task) sem alterar o comportamento em runtime.
class VoiceSession: ObservableObject, @unchecked Sendable {
    static let shared = VoiceSession()
    
    @Published var sessionState: SessionState = .idle
    @Published var connectionState: HermesConnectionState = .disconnected
    @Published var isCallActive: Bool = false
    @Published var isMuted: Bool = false
    @Published var errorMessage: String? = nil
    @Published var currentTranscript: String = ""
    @Published var hermesResponse: String = ""
    @Published var connectionLog: String = ""
    @Published var modelInfo: HermesAgentClient.ModelInfo? = nil

    private var cancellables = Set<AnyCancellable>()
    private var accumulatedResponse = ""
    private var lastPrompt = ""
    
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

        refreshModelInfo()
    }

    // MARK: - Ações Públicas
    func startCall() {
        CallManager.shared.startCall()
    }

    /// Consulta o modelo/motor ativo no servidor para exibir na tela principal.
    /// Falha silenciosamente (degrada bem, igual ao botão "Testar conexão").
    func refreshModelInfo() {
        Task {
            if let info = try? await HermesAgentClient.shared.fetchModelInfo() {
                await MainActor.run { self.modelInfo = info }
            }
        }
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
            self.hermesResponse = ""
            self.lastPrompt = ""
        }
        HermesLiveActivityController.start(
            status: "Conectando",
            prompt: "Chamada Hermes Voice ativa.",
            response: "Preparando microfone e conexão com o Hermes."
        )
        
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
                    self.refreshModelInfo()
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
                updateLiveActivity(
                    status: "Ouvindo",
                    prompt: "Fale com o Hermes.",
                    response: "Áudio roteado pela chamada do sistema."
                )
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
            await HermesLiveActivityController.end()
        }
        
        DispatchQueue.main.async {
            self.sessionState = .idle
            self.isCallActive = false
            self.isMuted = false
            self.currentTranscript = ""
            self.hermesResponse = ""
            self.lastPrompt = ""
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
        updateLiveActivity(
            status: "Ouvindo",
            prompt: text.isEmpty ? "Fale com o Hermes." : text,
            response: "Transcrevendo sua fala."
        )
    }
    
    func speechRecognizerDidDetectSilence(withText text: String) {
        print("Silêncio detectado. Enviando texto final: \(text)")
        lastPrompt = text
        
        DispatchQueue.main.async {
            self.sessionState = .processing
            self.currentTranscript = text
        }
        updateLiveActivity(
            status: "Processando",
            prompt: text,
            response: "Hermes está preparando a resposta."
        )
        
        // Pausa reconhecimento para evitar eco e capturar resposta
        SpeechRecognizer.shared.stopRecording()
        
        Task {
            do {
                accumulatedResponse = ""
                DispatchQueue.main.async { self.hermesResponse = "" }
                let rate = SettingsStore.shared.ttsRate

                // Fala incremental: começa a narrar assim que a primeira frase fica pronta,
                // em vez de esperar a resposta inteira. Reduz muito o atraso percebido.
                SpeechSynthesizer.shared.beginTurn()
                var buffer = ""

                // Pede a resposta em streaming ao API server do Hermes
                let stream = HermesAgentClient.shared.send(text)

                for try await chunk in stream {
                    accumulatedResponse += chunk
                    // Atualiza a transcrição da resposta ao vivo, conforme os tokens chegam
                    let current = accumulatedResponse
                    DispatchQueue.main.async { self.hermesResponse = current }
                    updateLiveActivity(
                        status: "Respondendo",
                        prompt: text,
                        response: current
                    )

                    // Enfileira as frases completas para fala imediata
                    buffer += chunk
                    while let sentence = self.nextSentence(from: &buffer) {
                        SpeechSynthesizer.shared.enqueue(sentence, rate: rate)
                    }
                }

                // Fala o que sobrou (última frase, possivelmente sem pontuação final)
                let remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainder.isEmpty {
                    SpeechSynthesizer.shared.enqueue(remainder, rate: rate)
                }
                // Fecha o turno. Se a resposta veio vazia, o sintetizador avisa o fim
                // e o app volta a ouvir automaticamente.
                SpeechSynthesizer.shared.endTurn()
            } catch {
                print("Erro ao enviar ou receber do Hermes: \(error.localizedDescription)")
                SpeechSynthesizer.shared.stop()
                DispatchQueue.main.async {
                    self.sessionState = .listening
                    try? SpeechRecognizer.shared.startRecording()
                }
                updateLiveActivity(
                    status: "Ouvindo",
                    prompt: "Fale com o Hermes.",
                    response: "Não foi possível completar a última resposta."
                )
            }
        }
    }

    /// Extrai a próxima frase completa do buffer (pontuação de fim seguida de espaço,
    /// ou quebra de linha), deixando o texto ainda incompleto no buffer. Evita cortar
    /// números/decimais no meio (só divide quando há espaço após a pontuação).
    private func nextSentence(from buffer: inout String) -> String? {
        while let first = buffer.first, first.isWhitespace { buffer.removeFirst() }
        let enders: Set<Character> = [".", "!", "?", "…"]
        var idx = buffer.startIndex
        while idx < buffer.endIndex {
            let ch = buffer[idx]
            let next = buffer.index(after: idx)
            if ch.isNewline {
                let sentence = String(buffer[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer = next < buffer.endIndex ? String(buffer[next...]) : ""
                return sentence.isEmpty ? nil : sentence
            }
            if enders.contains(ch), next < buffer.endIndex, buffer[next].isWhitespace {
                let sentence = String(buffer[...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer = String(buffer[next...])
                return sentence.isEmpty ? nil : sentence
            }
            idx = next
        }
        return nil
    }

    private func updateLiveActivity(status: String, prompt: String, response: String) {
        Task {
            await HermesLiveActivityController.update(
                status: status,
                prompt: prompt,
                response: response
            )
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
        updateLiveActivity(
            status: "Falando",
            prompt: lastPrompt.isEmpty ? "Hermes Voice" : lastPrompt,
            response: hermesResponse.isEmpty ? "Hermes está falando." : hermesResponse
        )
        SpeechRecognizer.shared.stopRecording()
    }
    
    func speechSynthesizerDidFinishSpeaking() {
        DispatchQueue.main.async {
            self.sessionState = .listening
        }
        updateLiveActivity(
            status: "Ouvindo",
            prompt: "Fale com o Hermes.",
            response: hermesResponse.isEmpty ? "Pronto para o próximo comando." : hermesResponse
        )
        // Retorna a ouvir o microfone após o término da fala do Hermes, caso não esteja mutado
        if !isMuted {
            try? SpeechRecognizer.shared.startRecording()
        }
    }
}
