import Foundation
import AVFoundation

protocol SpeechSynthesizerDelegate: AnyObject {
    func speechSynthesizerDidStartSpeaking()
    func speechSynthesizerDidFinishSpeaking()
}

class SpeechSynthesizer: NSObject {
    static let shared = SpeechSynthesizer()

    private let synthesizer = AVSpeechSynthesizer()
    weak var delegate: SpeechSynthesizerDelegate?
    private var voice: AVSpeechSynthesisVoice?

    // Controle de turno para fala incremental (frase a frase enquanto o texto chega).
    private var pendingUtterances = 0
    private var turnOpen = false
    private var didNotifyStart = false

    private override init() {
        super.init()
        self.synthesizer.delegate = self
        // REGRA DE OURO: reproduz através da rota de áudio da chamada do CallKit
        self.synthesizer.usesApplicationAudioSession = true
        configureVoice()
    }

    func configureVoice(locale: String = "pt-BR") {
        self.voice = AVSpeechSynthesisVoice(language: locale)
    }

    // MARK: - Fala incremental

    /// Inicia um novo turno de fala, cancelando o anterior.
    func beginTurn() {
        DispatchQueue.main.async {
            self.synthesizer.stopSpeaking(at: .immediate)
            self.pendingUtterances = 0
            self.turnOpen = true
            self.didNotifyStart = false
        }
    }

    /// Enfileira uma frase para ser falada (sem interromper as anteriores).
    func enqueue(_ text: String, rate: Float = 0.5) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DispatchQueue.main.async {
            let utterance = AVSpeechUtterance(string: trimmed)
            utterance.voice = self.voice
            utterance.rate = rate
            self.pendingUtterances += 1
            self.synthesizer.speak(utterance)
        }
    }

    /// Marca o fim do turno. Se não houver nada na fila, avisa que terminou (volta a ouvir).
    func endTurn() {
        DispatchQueue.main.async {
            self.turnOpen = false
            if self.pendingUtterances == 0 {
                self.delegate?.speechSynthesizerDidFinishSpeaking()
            }
        }
    }

    // MARK: - Fala imediata (uma vez só) — mantida por compatibilidade

    func speak(_ text: String, rate: Float = 0.5) {
        beginTurn()
        enqueue(text, rate: rate)
        endTurn()
    }

    func stop() {
        DispatchQueue.main.async {
            self.turnOpen = false
            self.pendingUtterances = 0
            self.synthesizer.stopSpeaking(at: .immediate)
        }
    }

    var isSpeaking: Bool {
        return synthesizer.isSpeaking
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        // Notifica o início apenas na primeira frase do turno (pausa o microfone uma vez).
        if !didNotifyStart {
            didNotifyStart = true
            delegate?.speechSynthesizerDidStartSpeaking()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        pendingUtterances = max(0, pendingUtterances - 1)
        // Só volta a ouvir quando o turno foi fechado E a fila esvaziou.
        if pendingUtterances == 0 && !turnOpen {
            delegate?.speechSynthesizerDidFinishSpeaking()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        pendingUtterances = max(0, pendingUtterances - 1)
        if pendingUtterances == 0 && !turnOpen {
            delegate?.speechSynthesizerDidFinishSpeaking()
        }
    }
}
