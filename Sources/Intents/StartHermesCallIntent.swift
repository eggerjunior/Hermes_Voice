import AppIntents
import Foundation

struct StartHermesCallIntent: AppIntent {
    static var title: LocalizedStringResource = "Iniciar Hermes Voice"
    static var description = IntentDescription("Inicia uma chamada de voz com o agente Hermes.")

    // NÃO abre o app: roda em background para que o CallKit apresente a chamada
    // mesmo com a tela bloqueada (sem exigir desbloqueio). O áudio/microfone é
    // gerenciado pela sessão de chamada VoIP do CallKit, que funciona bloqueada.
    static var openAppWhenRun: Bool = false

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
