import Foundation
import Speech
import AVFoundation

protocol SpeechRecognizerDelegate: AnyObject {
    func speechRecognizerDidRecognizeText(_ text: String)
    func speechRecognizerDidDetectSilence(withText text: String)
}

class SpeechRecognizer {
    static let shared = SpeechRecognizer()
    
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    weak var delegate: SpeechRecognizerDelegate?
    
    private var silenceTimer: Timer?
    private let silenceDuration: TimeInterval = 1.2
    
    private var isListening = false
    private var lastRecognizedText = ""
    
    private init() {}
    
    func configure(localeIdentifier: String) {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }
    
    static func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { recordGranted in
                    DispatchQueue.main.async {
                        completion(authStatus == .authorized && recordGranted)
                    }
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { recordGranted in
                    DispatchQueue.main.async {
                        completion(authStatus == .authorized && recordGranted)
                    }
                }
            }
        }
    }
    
    func startRecording() throws {
        stopRecording()
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw NSError(domain: "SpeechRecognizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Reconhecedor de fala indisponível ou em uso."])
        }
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        self.recognitionRequest = request
        
        // Retorna resultados parciais conforme o usuário fala
        request.shouldReportPartialResults = true
        
        // Habilita reconhecimento local no dispositivo se suportado
        if #available(iOS 13.0, *), speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        
        lastRecognizedText = ""
        isListening = true
        
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !trimmed.isEmpty, trimmed != self.lastRecognizedText {
                    self.lastRecognizedText = trimmed
                    self.delegate?.speechRecognizerDidRecognizeText(trimmed)
                    
                    // Reinicia o timer de silêncio para identificar o fim de fala do usuário
                    self.resetSilenceTimer()
                }
            }
            
            if error != nil {
                // Em caso de erro, interrompemos
                self.stopRecording()
            }
        }
    }
    
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }
    
    func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isListening = false
    }
    
    private func resetSilenceTimer() {
        // Agendado no run loop principal: os callbacks do SFSpeechRecognitionTask chegam
        // em filas arbitrárias (sem run loop), o que impediria o Timer de disparar com o
        // app em background / tela bloqueada. Garantir a main run loop mantém o fim de
        // fala funcionando durante a chamada VoIP bloqueada.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.silenceTimer?.invalidate()
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: self.silenceDuration, repeats: false) { [weak self] _ in
                guard let self = self, self.isListening else { return }

                if !self.lastRecognizedText.isEmpty {
                    let textToSend = self.lastRecognizedText
                    self.lastRecognizedText = "" // Limpa o buffer de texto para o próximo turno
                    self.delegate?.speechRecognizerDidDetectSilence(withText: textToSend)
                }
            }
        }
    }
}
