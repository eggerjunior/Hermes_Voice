import AppIntents
import Foundation

struct StartHermesCallIntent: AppIntent {
    static var title: LocalizedStringResource = "Conversar com o Hermes"
    static var description = IntentDescription("Inicia uma chamada de voz com o agente Hermes.")

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        // Dispara o fluxo de chamada do CallKit
        VoiceSession.shared.startCall()
        return .result(value: "Iniciando chamada com o Hermes")
    }
}

struct HermesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartHermesCallIntent(),
            phrases: [
                "Falar com o \(.applicationName)",
                "Conversar com o \(.applicationName)",
                "Chamar o \(.applicationName)"
            ],
            shortTitle: "Falar com o Hermes",
            systemImageName: "phone.fill"
        )
    }
}
