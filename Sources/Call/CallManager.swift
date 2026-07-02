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
    
    private var provider: CXProvider
    private let callController = CXCallController()
    private var activeCallUUID: UUID?

    weak var delegate: CallManagerDelegate?

    // CXProviderConfiguration() (iOS 14+); o nome exibido na chamada vem do CXHandle
    // ("Hermes Voice") e do nome do app — evita o init(localizedName:) depreciado.
    private static func makeConfiguration() -> CXProviderConfiguration {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        // Padrão é 2. Elevado para absorver "grupos de chamada" presos e invisíveis
        // de sessões anteriores (causa do error 6 / maximumCallGroupsReached ao
        // iniciar pelo Atalhos em cold start), permitindo iniciar a nova chamada.
        configuration.maximumCallGroups = 8
        configuration.supportedHandleTypes = [.generic]
        return configuration
    }

    private override init() {
        self.provider = CXProvider(configuration: Self.makeConfiguration())
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    /// Recria o provider do zero. `invalidate()` encerra TODAS as chamadas associadas,
    /// limpando qualquer chamada presa que cause o CallKit error 6
    /// (maximumCallGroupsReached) — comum ao iniciar pelo app Atalhos em cold start.
    private func resetProvider() {
        provider.invalidate()
        provider = CXProvider(configuration: Self.makeConfiguration())
        provider.setDelegate(self, queue: nil)
    }

    func startCall() {
        // Encerra chamadas remanescentes conhecidas antes de iniciar uma nova.
        let lingering = callController.callObserver.calls.filter { !$0.hasEnded }
        if lingering.isEmpty {
            requestStartCall(retryOnBusy: true)
        } else {
            let endActions = lingering.map { CXEndCallAction(call: $0.uuid) }
            callController.request(CXTransaction(actions: endActions)) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.requestStartCall(retryOnBusy: true)
                }
            }
        }
    }

    // Snapshot do estado de chamadas visível ao app — diagnóstico do error 6.
    private func callStateSnapshot() -> String {
        let calls = callController.callObserver.calls
        if calls.isEmpty { return "obs=0" }
        let parts = calls.prefix(4).map { c -> String in
            let id = String(c.uuid.uuidString.prefix(8))
            return "\(id)[end:\(c.hasEnded ? 1 : 0) conn:\(c.hasConnected ? 1 : 0) out:\(c.isOutgoing ? 1 : 0)]"
        }
        return "obs=\(calls.count) " + parts.joined(separator: " ")
    }

    private func requestStartCall(retryOnBusy: Bool, priorInfo: String = "") {
        let uuid = UUID()
        self.activeCallUUID = uuid
        let handle = CXHandle(type: .generic, value: "Hermes Voice")
        let startCallAction = CXStartCallAction(call: uuid, handle: handle)

        let transaction = CXTransaction(action: startCallAction)
        callController.request(transaction) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                let nsError = error as NSError
                let snap = self.callStateSnapshot()
                // O domínio bridgeado do erro varia; código 6 numa falha de
                // CXStartCallAction = maximumCallGroupsReached (grupo preso).
                let isBusy = nsError.code == CXErrorCodeRequestTransactionError.maximumCallGroupsReached.rawValue
                if isBusy && retryOnBusy {
                    // Chamada presa: recria o provider (encerra tudo) e tenta 1x de novo.
                    print("CallKit ocupado (error 6). Reset+retry. pre=\(snap)")
                    self.resetProvider()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.requestStartCall(retryOnBusy: false, priorInfo: "pre:\(snap)")
                    }
                    return
                }
                print("Erro CXStartCallAction: \(error.localizedDescription) | \(priorInfo) post:\(snap)")
                // Erro enriquecido com o estado das chamadas (diagnóstico do error 6).
                let detail = "CallKit code=\(nsError.code) \(priorInfo) post:\(snap)"
                let enriched = NSError(domain: nsError.domain, code: nsError.code,
                                       userInfo: [NSLocalizedDescriptionKey: detail])
                DispatchQueue.main.async {
                    self.delegate?.callManagerDidFail(withError: enriched)
                }
            } else {
                // Notifica o CallKit que a chamada iniciou a conexão e foi conectada com sucesso
                self.provider.reportOutgoingCall(with: uuid, startedConnectingAt: nil)
                self.provider.reportOutgoingCall(with: uuid, connectedAt: nil)
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
