import AppIntents
import Foundation

struct StartHermesCallIntent: AppIntent {
    static var title: LocalizedStringResource = "Iniciar Hermes Voice"
    static var description = IntentDescription("Inicia uma chamada de voz com o agente Hermes.")

    // Abre o app ao executar: a chamada precisa de microfone e áudio em foreground.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        // Dispara o fluxo de chamada do CallKit
        VoiceSession.shared.startCall()
        return .result(value: "Iniciando o Hermes Voice")
    }
}

struct HermesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartHermesCallIntent(),
            phrases: [
                "Iniciar \(.applicationName)",
                "Iniciar o \(.applicationName)",
                "Abrir \(.applicationName)",
                "Falar com o \(.applicationName)",
                "Conversar com o \(.applicationName)",
                "Chamar o \(.applicationName)"
            ],
            shortTitle: "Iniciar Hermes Voice",
            systemImageName: "phone.fill"
        )
    }
}
