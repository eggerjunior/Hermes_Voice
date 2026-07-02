import AppIntents
import Foundation

struct StartHermesCallIntent: AppIntent {
    static var title: LocalizedStringResource = "Iniciar Hermes Voice"
    static var description = IntentDescription("Inicia uma chamada de voz com o agente Hermes.")

    // Abre o app (foreground) ao executar. É obrigatório: iniciar uma chamada CallKit
    // (CXStartCallAction) a partir de um App Intent em background falha com error 6
    // (invalidAction) — limitação documentada do iOS. Com o app em foreground funciona
    // (era o comportamento original que funcionava). O hands-free 100% na tela bloqueada
    // depende da entitlement de CarPlay Communication (aprovação da Apple).
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
