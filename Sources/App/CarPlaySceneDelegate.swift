import CarPlay
import Combine
import UIKit

/// Cena CarPlay do Hermes Voice. Usa CPVoiceControlTemplate (a mesma tela nativa de
/// "assistente de voz" do Jarvis) em vez de um CPListTemplate com texto estático —
/// dá a animação de microfone/ouvindo/pensando/falando ao vivo, e não parece uma
/// ligação telefônica. Aciona a `VoiceSession` diretamente (em vez de depender de uma
/// notificação ouvida pela `RootView`), pois quando o CarPlay conecta sem o app estar
/// aberto no iPhone a `RootView` nunca chega a existir e ninguém escuta a notificação.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPInterfaceControllerDelegate {
    private var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()
    private let session = VoiceSession.shared

    private var isPushingVoiceControl = false
    private var isPoppingToRoot = false
    private var voiceControlTemplateIsOnStack = false

    private let listItem = CPListItem(text: "Diga “Ei Hermes”", detailText: "Toque para ativar a conversa por voz")

    private lazy var listTemplate: CPListTemplate = {
        listItem.handler = { [weak self] _, completion in
            self?.toggleHermes()
            completion()
        }
        let section = CPListSection(items: [listItem])
        return CPListTemplate(title: "Hermes Voice", sections: [section])
    }()

    /// Rótulo curto de provedor/modelo (ex.: "gpt-4o · OpenAI") anexado ao detail
    /// text da lista raiz e ao título do estado "idle" da tela de voz — os únicos
    /// dois lugares fixos disponíveis nos templates nativos do CarPlay.
    private func modelLabel(from info: HermesAgentClient.ModelInfo?) -> String? {
        guard let info else { return nil }
        return "\(info.model) · \(info.provider)"
    }

    private var currentModelLabel: String?

    /// CPVoiceControlState/Template são imutáveis após criados — não dá para
    /// atualizar o título de um estado já existente. Por isso o template inteiro é
    /// reconstruído sob demanda (só antes de apresentar, nunca com ele já na tela)
    /// toda vez que o modelo/provedor ativo muda.
    private lazy var voiceControlTemplate: CPVoiceControlTemplate = makeVoiceControlTemplate()

    private func makeVoiceControlTemplate() -> CPVoiceControlTemplate {
        let idleTitle: String
        if let label = currentModelLabel {
            idleTitle = "Diga “Ei Hermes” (\(label))"
        } else {
            idleTitle = "Diga “Ei Hermes”"
        }
        let states = [
            CPVoiceControlState(identifier: "idle", titleVariants: [idleTitle, "Diga “Ei Hermes”"], image: UIImage(systemName: "mic"), repeats: false),
            CPVoiceControlState(identifier: "listening", titleVariants: ["Ouvindo…"], image: UIImage(systemName: "waveform"), repeats: true),
            CPVoiceControlState(identifier: "processing", titleVariants: ["Processando…"], image: UIImage(systemName: "ellipsis.circle"), repeats: true),
            CPVoiceControlState(identifier: "speaking", titleVariants: ["Hermes falando…"], image: UIImage(systemName: "speaker.wave.2"), repeats: true),
            CPVoiceControlState(identifier: "error", titleVariants: ["Algo falhou. Volte e tente de novo."], image: UIImage(systemName: "exclamationmark.triangle"), repeats: false)
        ]
        return CPVoiceControlTemplate(voiceControlStates: states)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.delegate = self
        interfaceController.setRootTemplate(listTemplate, animated: false) { [weak self] _, _ in
            guard let self else { return }
            self.observeSession()
            if self.session.isCallActive {
                self.presentVoiceControl()
            }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        isPushingVoiceControl = false
        isPoppingToRoot = false
        voiceControlTemplateIsOnStack = false
        self.interfaceController = nil
    }

    private func toggleHermes() {
        if session.isCallActive {
            session.endCall()
        } else {
            presentVoiceControl()
            session.startCall()
        }
    }

    func templateDidDisappear(_ aTemplate: CPTemplate, animated: Bool) {
        guard aTemplate === voiceControlTemplate else { return }
        voiceControlTemplateIsOnStack = false
        if session.isCallActive {
            session.endCall()
        }
    }

    /// CPVoiceControlTemplate é modal: precisa ser apresentado/dispensado com
    /// present/dismissTemplate, nunca push/popTemplate. Ao empurrá-lo na pilha de
    /// navegação (como antes), o X nativo do template — que só funciona junto do
    /// fluxo present/dismiss — ficava sem nenhuma ação associada, e o CarPlay não
    /// encerrava direito o indicador de "chamada" ao voltar.
    private func presentVoiceControl() {
        guard !isPushingVoiceControl, interfaceController?.topTemplate !== voiceControlTemplate else { return }
        isPushingVoiceControl = true
        voiceControlTemplate = makeVoiceControlTemplate()
        interfaceController?.presentTemplate(voiceControlTemplate, animated: true) { [weak self] _, _ in
            guard let self else { return }
            self.isPushingVoiceControl = false
            self.voiceControlTemplateIsOnStack = true
            self.updateVoiceControlState(for: self.session.sessionState)
        }
    }

    private func popToRootIfNeeded() {
        guard !isPoppingToRoot, interfaceController?.topTemplate === voiceControlTemplate else { return }
        isPoppingToRoot = true
        interfaceController?.dismissTemplate(animated: true) { [weak self] _, _ in
            guard let self else { return }
            self.isPoppingToRoot = false
            self.voiceControlTemplateIsOnStack = false
        }
    }

    private func presentError(_ message: String) {
        let action = CPAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(titleVariants: [message], actions: [action])
        interfaceController?.presentTemplate(alert, animated: true, completion: nil)
    }

    /// Mantém a lista e a tela de voz sincronizadas com o estado real da conversa,
    /// incluindo chamadas iniciadas pelo iPhone (ex.: o motorista deu play no telefone
    /// antes de conectar no CarPlay).
    private func observeSession() {
        session.$sessionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateVoiceControlState(for: state)
            }
            .store(in: &cancellables)

        session.$isCallActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCallActive in
                self?.listItem.setText(isCallActive ? "Hermes ativo" : "Diga “Ei Hermes”")
                if isCallActive {
                    self?.presentVoiceControl()
                } else {
                    self?.popToRootIfNeeded()
                }
            }
            .store(in: &cancellables)

        session.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.presentError(message)
            }
            .store(in: &cancellables)

        session.$modelInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                self.currentModelLabel = self.modelLabel(from: info)
                let base = "Toque para ativar a conversa por voz"
                self.listItem.setDetailText(self.currentModelLabel.map { "\(base) · \($0)" } ?? base)
            }
            .store(in: &cancellables)
    }

    private func updateVoiceControlState(for state: SessionState) {
        guard voiceControlTemplateIsOnStack, session.isCallActive else { return }
        switch state {
        case .idle: voiceControlTemplate.activateVoiceControlState(withIdentifier: "idle")
        case .listening: voiceControlTemplate.activateVoiceControlState(withIdentifier: "listening")
        case .processing: voiceControlTemplate.activateVoiceControlState(withIdentifier: "processing")
        case .speaking: voiceControlTemplate.activateVoiceControlState(withIdentifier: "speaking")
        }
    }
}
