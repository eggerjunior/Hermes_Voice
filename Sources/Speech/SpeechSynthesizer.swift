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
    
    private override init() {
        super.init()
        self.synthesizer.delegate = self
        // REGRA DE OURO: Faz o sintetizador reproduzir através da rota de áudio da chamada do CallKit
        self.synthesizer.usesApplicationAudioSession = true
        configureVoice()
    }
    
    func configureVoice(locale: String = "pt-BR") {
        self.voice = AVSpeechSynthesisVoice(language: locale)
    }
    
    func speak(_ text: String, rate: Float = 0.5) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        
        synthesizer.speak(utterance)
    }
    
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    var isSpeaking: Bool {
        return synthesizer.isSpeaking
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        delegate?.speechSynthesizerDidStartSpeaking()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        delegate?.speechSynthesizerDidFinishSpeaking()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        delegate?.speechSynthesizerDidFinishSpeaking()
    }
}
