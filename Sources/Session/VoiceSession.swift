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
    @Published var providerLabel: String? = nil

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
        AudioEngineManager.shared.delegate = self
        SpeechRecognizer.shared.delegate = self
        SpeechSynthesizer.shared.delegate = self

        refreshModelInfo()
        refreshProviderLabel()
    }

    // MARK: - Ações Públicas
    func startCall() {
        guard !isCallActive else { return }
        activateAudioSession()
        startAudioAndAgent()
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

    /// Consulta o catálogo de providers para exibir o nome comercial (ex.: "Google
    /// Gemini") do provider ativo, complementando `modelInfo` (que só traz o motor,
    /// ex.: "gemini") na tela principal.
    func refreshProviderLabel() {
        Task {
            if let catalog = try? await HermesAgentClient.shared.fetchAvailableModels() {
                let label = catalog.providers.first(where: { $0.id == catalog.activeProvider })?.label
                await MainActor.run { self.providerLabel = label ?? catalog.activeProvider }
            }
        }
    }

    func endCall() {
        guard isCallActive else { return }
        stopAudioAndAgent()
        deactivateAudioSession()
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            SpeechRecognizer.shared.stopRecording()
        } else if sessionState == .listening || sessionState == .speaking {
            try? SpeechRecognizer.shared.startRecording()
        }
    }

    /// Palavra de ativação que interrompe o Hermes enquanto ele fala (estilo Jarvis):
    /// dito o nome, ele para na hora e volta a ouvir. Comparação sem acento/maiúsculas
    /// e por substring — cobre "Hermes", "Ei Hermes", "Hermes, pera" etc.
    private func containsWakeWord(_ text: String) -> Bool {
        let normalized = text.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        return normalized.contains("hermes")
    }

    /// Ativa a sessão de áudio direto (sem CallKit — igual ao Jarvis), para não
    /// aparecer como "chamada telefônica" na tela de bloqueio/CarPlay. `.voiceChat`
    /// habilita o cancelamento de eco do sistema; `.defaultToSpeaker` dá viva-voz como
    /// padrão, mas ainda respeita fones/Bluetooth/carro quando conectados.
    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let externalPorts: [AVAudioSession.Port] = [
                .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio, .usbAudio
            ]
            let hasExternalOutput = session.currentRoute.outputs.contains { externalPorts.contains($0.portType) }
            if !hasExternalOutput {
                try? session.overrideOutputAudioPort(.speaker)
            }
        } catch {
            errorMessage = "Erro ao ativar a sessão de áudio: \(error.localizedDescription)"
        }
    }

    /// O motor de áudio acabou de parar (removeTap + engine.stop()); o thread de render
    /// do Core Audio pode levar um instante para liberar o hardware do microfone. Se
    /// `setActive(false)` for chamado enquanto ele ainda está desligando, a chamada falha
    /// silenciosamente (ver `try?` original) e a sessão fica presa em `.playAndRecord`
    /// ativa — é isso que deixava o indicador de microfone do sistema aceso mesmo depois
    /// da ligação encerrada. Tenta de novo em caso de falha.
    private func deactivateAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
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
                    self.refreshProviderLabel()
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

// MARK: - AudioEngineManagerDelegate
extension VoiceSession: AudioEngineManagerDelegate {
    func audioEngineDidReceiveBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Encaminha buffers de áudio do tap para o STT quando estamos ouvindo o usuário,
        // e também enquanto o Hermes fala (para captar a palavra de ativação de interrupção).
        // (Um filtro de nível de microfone para reduzir autointerrupção por eco foi tentado
        // aqui e removido: o AEC do sistema já abafa bastante o microfone enquanto o
        // alto-falante toca, então o limiar também cortava a fala real do usuário e a
        // palavra de ativação parava de funcionar.)
        if (sessionState == .listening || sessionState == .speaking) && !isMuted {
            SpeechRecognizer.shared.appendAudioBuffer(buffer)
        }
    }
}

// MARK: - SpeechRecognizerDelegate
extension VoiceSession: SpeechRecognizerDelegate {
    func speechRecognizerDidRecognizeText(_ text: String) {
        // Enquanto o Hermes fala, o reconhecedor só está ativo para ouvir a palavra de
        // ativação — não tratamos o parcial como transcrição de um novo turno.
        if sessionState == .speaking {
            if containsWakeWord(text) {
                print("Palavra de ativação detectada durante a fala: interrompendo o Hermes.")
                SpeechSynthesizer.shared.stop()
            }
            return
        }

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

    /// O reconhecimento de fala morreu sozinho (erro do SFSpeechRecognizer) enquanto
    /// deveríamos estar ouvindo — sem isso o app fica preso em "Ouvindo..." para sempre,
    /// já que nenhum resultado novo chega para acionar o timer de silêncio. Tenta
    /// reiniciar uma vez após um pequeno atraso (evita loop apertado se o erro persistir)
    /// e reconfere o estado no momento do disparo, caso a ligação já tenha mudado.
    func speechRecognizerDidFail() {
        guard (sessionState == .listening || sessionState == .speaking), !isMuted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            guard (self.sessionState == .listening || self.sessionState == .speaking), !self.isMuted else { return }
            try? SpeechRecognizer.shared.startRecording()
        }
    }

    func speechRecognizerDidDetectSilence(withText text: String) {
        // Ignora silêncio detectado enquanto o Hermes fala — nesse estado o reconhecedor
        // só está ativo para captar a palavra de ativação (ver speechRecognizerDidRecognizeText).
        guard sessionState != .speaking else { return }

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
        // Mantém o microfone ativo (em vez de parar) para poder ouvir a palavra de
        // ativação e interromper o Hermes no meio da fala, como o Jarvis faz.
        if !isMuted {
            try? SpeechRecognizer.shared.startRecording()
        }
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
