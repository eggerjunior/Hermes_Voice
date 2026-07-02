import Foundation
import CallKit
import AVFoundation

protocol CallManagerDelegate: AnyObject {
    func callManagerDidActivateAudio()
    func callManagerDidDeactivateAudio()
    func callManagerDidEndCall()
    func callManagerDidMute(_ muted: Bool)
    func callManagerDidFail(withError error: Error)
}

class CallManager: NSObject {
    static let shared = CallManager()
    
    private let provider: CXProvider
    private let callController = CXCallController()
    private var activeCallUUID: UUID?
    
    weak var delegate: CallManagerDelegate?
    
    private override init() {
        let configuration = CXProviderConfiguration(localizedName: "Hermes Voice")
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        
        self.provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }
    
    func startCall() {
        let uuid = UUID()
        self.activeCallUUID = uuid
        let handle = CXHandle(type: .generic, value: "Hermes Voice")
        let startCallAction = CXStartCallAction(call: uuid, handle: handle)
        
        let transaction = CXTransaction(action: startCallAction)
        callController.request(transaction) { [weak self] error in
            if let error = error {
                print("Erro ao solicitar transação de chamada (CXStartCallAction): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.delegate?.callManagerDidFail(withError: error)
                }
            } else {
                // Notifica o CallKit que a chamada iniciou a conexão e foi conectada com sucesso
                self?.provider.reportOutgoingCall(with: uuid, startedConnectingAt: nil)
                self?.provider.reportOutgoingCall(with: uuid, connectedAt: nil)
            }
        }
    }
    
    func endCall() {
        guard let uuid = activeCallUUID else { return }
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        callController.request(transaction) { error in
            if let error = error {
                print("Erro ao solicitar encerramento da chamada: \(error.localizedDescription)")
            }
        }
    }
    
    func setMuted(_ isMuted: Bool) {
        guard let uuid = activeCallUUID else { return }
        let muteAction = CXSetMutedCallAction(call: uuid, muted: isMuted)
        let transaction = CXTransaction(action: muteAction)
        callController.request(transaction) { error in
            if let error = error {
                print("Erro ao solicitar alteração de mudo: \(error.localizedDescription)")
            }
        }
    }
}

extension CallManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        activeCallUUID = nil
        delegate?.callManagerDidEndCall()
    }
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // REGRA DE OURO: Apenas define a categoria de áudio, nunca chama AVAudioSession.setActive(true)
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers]
            )
            action.fulfill()
        } catch {
            print("Erro ao configurar categoria de áudio no CXStartCallAction: \(error.localizedDescription)")
            action.fail()
        }
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        activeCallUUID = nil
        delegate?.callManagerDidEndCall()
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        delegate?.callManagerDidMute(action.isMuted)
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // A ativação real do áudio foi gerenciada pelo CallKit. Agora iniciamos o motor de áudio e STT.
        delegate?.callManagerDidActivateAudio()
    }
    
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        // Chamado quando o sistema CallKit desativa o áudio (ex. chamada concorrente ou desligou).
        delegate?.callManagerDidDeactivateAudio()
    }
}
