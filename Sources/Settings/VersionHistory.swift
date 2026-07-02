import Foundation

struct VersionEntry: Identifiable {
    let id = UUID()
    let version: String
    let build: String
    let date: String
    let changes: [String]
    let isCurrent: Bool
}

class VersionManager {
    static let shared = VersionManager()
    
    private init() {}
    
    // Retorna a versão de marketing (ex: 1.0.5) e o número de build (ex: 6)
    var currentVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "11"
        return "\(version) (Build \(build))"
    }
    
    // Lê dinamicamente a data e hora em que o aplicativo foi compilado no Mac
    var currentBuildDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: Self.buildDate)
    }
    
    private static var buildDate: Date {
        // Lê a data de modificação do arquivo executável do aplicativo, que é atualizado obrigatoriamente a cada build
        if let executableName = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String,
           let executableURL = Bundle.main.url(forResource: executableName, withExtension: nil),
           let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            return modificationDate
        }
        return Date()
    }
    
    // Histórico de alterações do aplicativo com datas e mudanças realizadas
    let history: [VersionEntry] = [
        VersionEntry(
            version: "1.2.1",
            build: "11",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "Funcionamento com a tela bloqueada: o comando Siri inicia a chamada via CallKit em background (sem exigir desbloqueio).",
                "Detecção de fim de fala movida para o run loop principal (confiável em background).",
                "Nome da chamada no CallKit atualizado para \"Hermes Voice\".",
                "App definido como iPhone-only e orientação retrato declarada (requisitos de bundle para TestFlight)."
            ],
            isCurrent: true
        ),
        VersionEntry(
            version: "1.2.0",
            build: "9",
            date: "02/07/2026 00:00:00",
            changes: [
                "Comando de voz Siri: \"Ei Siri, iniciar Hermes Voice\" inicia a chamada.",
                "App Shortcut aberto automaticamente ao acionar por voz (openAppWhenRun)."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.1.1",
            build: "8",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "Nome de exibição do app alterado para \"Hermes Voice\"."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.1.0",
            build: "7",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "Migração da conexão de WebSocket (dashboard) para o API server OpenAI-compatível do Hermes.",
                "Comunicação agora via HTTPS POST /v1/chat/completions com streaming SSE.",
                "Autenticação por API Key (Bearer) no lugar de Basic Auth; continuidade de conversa via X-Hermes-Session-Id.",
                "Adicionado botão \"Testar conexão\" nas Configurações (health check com feedback de sucesso/erro).",
                "Tela de conexão atualizada: campos \"URL da API\" e \"API Key\"."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.0.5",
            build: "6",
            date: "01/07/2026 22:20:00",
            changes: [
                "Adicionada visualização de histórico de alterações de versão (Changelog).",
                "Exibição dinâmica da versão, build e carimbo de data/hora da compilação atual.",
                "Implementado clique interativo no número da versão para exibir o histórico."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.0.4",
            build: "5",
            date: "01/07/2026 22:17:00",
            changes: [
                "Implementado botão de alternância de visibilidade da senha (exibir/ocultar olho).",
                "Melhoria na usabilidade da tela de conexões."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.0.3",
            build: "4",
            date: "01/07/2026 21:30:00",
            changes: [
                "Correção das APIs de permissão de microfone para suportar iOS 17+ (AVAudioApplication).",
                "Correção de avisos de compilação relacionados à concorrência do Swift."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.0.2",
            build: "3",
            date: "01/07/2026 21:05:00",
            changes: [
                "Correção na inicialização da configuração do CallKit (CXProviderConfiguration).",
                "Substituição de APIs de áudio obsoletas do AVAudioSession."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.0.1",
            build: "2",
            date: "01/07/2026 20:30:00",
            changes: [
                "Integração do motor de áudio (AVAudioEngine) com Cancelamento de Eco Acústico (AEC).",
                "Integração do Speech-to-Text (STT) local com temporizador de 1.2 segundos para fim de fala."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.0.0",
            build: "1",
            date: "01/07/2026 20:00:00",
            changes: [
                "Arquitetura inicial do aplicativo Hermes Voice.",
                "Configuração do XcodeGen, Info.plist e Entitlements nativos.",
                "Setup estrutural do CallKit para controle de chamada virtual."
            ],
            isCurrent: false
        )
    ]
}
