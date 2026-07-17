import CarPlay
import Combine
import UIKit

/// Cena CarPlay do Hermes Voice. Aciona a `VoiceSession` diretamente (em vez de depender
/// de uma notificação ouvida pela `RootView`), pois quando o CarPlay conecta sem o app
/// estar aberto no iPhone a `RootView` nunca chega a existir e ninguém escuta a notificação
/// — era por isso que tocar no item não fazia nada.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var listItem: CPListItem?
    private var cancellables = Set<AnyCancellable>()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let item = CPListItem(text: "Diga “Ei Hermes”", detailText: "Toque para ativar a conversa por voz")
        item.handler = { [weak self] _, completion in
            self?.toggleHermes()
            completion()
        }
        self.listItem = item

        let section = CPListSection(items: [item])
        let template = CPListTemplate(title: "Hermes Voice", sections: [section])
        interfaceController.setRootTemplate(template, animated: true, completion: nil)

        observeSession()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        self.interfaceController = nil
        self.listItem = nil
    }

    private func toggleHermes() {
        let session = VoiceSession.shared
        if session.isCallActive {
            session.endCall()
        } else {
            session.startCall()
        }
    }

    /// Mantém o item da lista sincronizado com o estado real da conversa, incluindo
    /// chamadas iniciadas pelo iPhone (ex.: o motorista deu play no telefone antes de
    /// conectar no CarPlay).
    private func observeSession() {
        let session = VoiceSession.shared

        Publishers.CombineLatest(session.$isCallActive, session.$sessionState)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCallActive, state in
                self?.updateListItem(isCallActive: isCallActive, state: state)
            }
            .store(in: &cancellables)

        session.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.presentError(message)
            }
            .store(in: &cancellables)
    }

    private func updateListItem(isCallActive: Bool, state: SessionState) {
        guard let item = listItem else { return }
        if isCallActive {
            item.setText("Encerrar conversa")
            item.setDetailText(state.rawValue)
        } else {
            item.setText("Diga “Ei Hermes”")
            item.setDetailText("Toque para ativar a conversa por voz")
        }
    }

    private func presentError(_ message: String) {
        guard let interfaceController = interfaceController else { return }
        let alert = CPAlertTemplate(titleVariants: [message], actions: [
            CPAlertAction(title: "OK", style: .default) { [weak interfaceController] _ in
                interfaceController?.dismissTemplate(animated: true, completion: nil)
            }
        ])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }
}
