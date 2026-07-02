import Foundation
import AVFoundation

protocol AudioEngineManagerDelegate: AnyObject {
    func audioEngineDidReceiveBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime)
}

class AudioEngineManager {
    static let shared = AudioEngineManager()
    
    private let audioEngine = AVAudioEngine()
    weak var delegate: AudioEngineManagerDelegate?
    private var isRunning = false
    
    private init() {}
    
    func start() throws {
        guard !isRunning else { return }
        
        let inputNode = audioEngine.inputNode
        
        // REGRA DE OURO: Habilita processamento de voz para cancelamento de eco acústico (AEC)
        // Isso impede que o microfone capture o áudio reproduzido pelo próprio alto-falante (ou do carro)
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            print("Aviso: Falha ao habilitar voice processing (AEC): \(error.localizedDescription)")
        }
        
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Remove qualquer tap anterior por segurança
        inputNode.removeTap(onBus: 0)
        
        // Instala tap de captura
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            self?.delegate?.audioEngineDidReceiveBuffer(buffer, time: time)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
    }
    
    func stop() {
        guard isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRunning = false
    }
}
