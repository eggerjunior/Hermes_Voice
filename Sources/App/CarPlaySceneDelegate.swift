import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let listeningItem = CPListItem(text: "Diga “Ei Hermes”", detailText: "Toque para ativar a conversa por voz")
        listeningItem.handler = { [weak self] _, completion in
            self?.activateHermes()
            completion()
        }

        let section = CPListSection(items: [listeningItem])
        let template = CPListTemplate(title: "Hermes Voice", sections: [section])
        interfaceController.setRootTemplate(template, animated: true, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func activateHermes() {
        NotificationCenter.default.post(name: .hermesCarPlayActivate, object: nil)
    }
}

extension Notification.Name {
    static let hermesCarPlayActivate = Notification.Name("hermesCarPlayActivate")
}
