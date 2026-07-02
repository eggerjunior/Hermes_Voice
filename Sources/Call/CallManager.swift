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
        // CXProviderConfiguration() (iOS 14+); o nome exibido na chamada vem do CXHandle
        // ("Hermes Voice") e do nome do app — evita o init(localizedName:) depreciado.
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        
        self.provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }
    
    func startCall() {
        // Encerra chamadas remanescentes antes de iniciar uma nova.
        // Evita o CallKit error 6 (maximumCallGroupsReached) quando uma chamada
        // anterior não foi finalizada (ex.: acionada de novo pelo app Atalhos).
        let lingering = callController.callObserver.calls.filter { !$0.hasEnded }
        guard !lingering.isEmpty else {
            requestStartCall()
            return
        }
        let endActions = lingering.map { CXEndCallAction(call: $0.uuid) }
        callController.request(CXTransaction(actions: endActions)) { [weak self] _ in
            self?.requestStartCall()
        }
    }

    private func requestStartCall() {
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
            // .defaultToSpeaker: viva-voz como saída padrão (como uma ligação em viva-voz),
            // mas ainda permitindo fones/Bluetooth/carro quando conectados.
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers]
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
        // Força viva-voz como padrão SOMENTE quando não há saída externa conectada.
        // Assim respeita fones/Bluetooth/carro (que têm prioridade), como uma ligação.
        let externalPorts: [AVAudioSession.Port] = [
            .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio, .usbAudio
        ]
        let hasExternalOutput = audioSession.currentRoute.outputs.contains { externalPorts.contains($0.portType) }
        if !hasExternalOutput {
            try? audioSession.overrideOutputAudioPort(.speaker)
        }

        // A ativação real do áudio foi gerenciada pelo CallKit. Agora iniciamos o motor de áudio e STT.
        delegate?.callManagerDidActivateAudio()
    }
    
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        // Chamado quando o sistema CallKit desativa o áudio (ex. chamada concorrente ou desligou).
        delegate?.callManagerDidDeactivateAudio()
    }
}
