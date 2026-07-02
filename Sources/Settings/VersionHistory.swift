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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.10"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "21"
        return "\(version) (Build \(build))"
    }
    
    // Hash do commit que gerou este build (injetado via GIT_COMMIT no build).
    var currentCommit: String {
        let commit = Bundle.main.infoDictionary?["GitCommit"] as? String ?? "dev"
        return commit.isEmpty ? "dev" : commit
    }

    // URL do commit no GitHub (nil quando build local sem hash, ex.: "dev").
    var commitURL: URL? {
        let commit = currentCommit
        guard commit != "dev" else { return nil }
        return URL(string: "https://github.com/eggerjunior/Hermes_Voice/commit/\(commit)")
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
            version: "1.2.10",
            build: "21",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "Atalho/Siri volta a funcionar: revertido para abrir o app ao iniciar (openAppWhenRun=true), como na versão original. O erro 6 vinha de rodar em background (limitação do iOS).",
                "Removido ajuste inútil de maximumCallGroups (baseado em diagnóstico incorreto).",
                "Hands-free 100% na tela bloqueada segue pendente da entitlement de CarPlay Communication."
            ],
            isCurrent: true
        ),
        VersionEntry(
            version: "1.2.9",
            build: "20",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "CallKit error 6 resolvido: grupo de chamada preso e invisível de sessões anteriores era a causa; elevado o limite de grupos (maximumCallGroups) para permitir iniciar a chamada pelo Atalhos.",
                "Corrigida a detecção do erro (o retry não estava disparando)."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.2.8",
            build: "19",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "Diagnóstico do CallKit error 6: o alerta de erro agora mostra o estado das chamadas (para rastrear a causa quando iniciado pelo Atalhos)."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.2.7",
            build: "18",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "Correção definitiva do CallKit error 6 ao iniciar pelo Atalhos: ao detectar chamada presa, recria o provider (encerra tudo) e tenta novamente."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.2.6",
            build: "17",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "Limpeza de avisos de compilação: init do CallKit atualizado, Sendable nos singletons e UIRequiresFullScreen (iPhone-only)."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.2.5",
            build: "16",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "Hash do commit exibido no rodapé, com link para abrir o commit no GitHub (navegador padrão).",
                "Commit também registrado no Log do Agente ao conectar."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.2.4",
            build: "15",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "Resposta mais ágil: fala incremental — começa a narrar assim que a primeira frase fica pronta, sem esperar a resposta inteira.",
                "Tempo de silêncio do reconhecimento reduzido de 1,2s para 0,8s."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.2.3",
            build: "14",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "Nova área de transcrição exibindo a resposta do Hermes ao vivo (streaming).",
                "Log do Agente: mostra os eventos de execução (envio, resposta, ferramentas e conclusão do turno)."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.2.2",
            build: "13",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "Viva-voz (alto-falante) como saída de áudio padrão, respeitando fones/Bluetooth/carro quando conectados.",
                "Corrige erro do CallKit (error 6) ao iniciar chamada pelo app Atalhos: encerra chamadas remanescentes antes de iniciar uma nova."
            ],
            isCurrent: false
        ),
        VersionEntry(
            version: "1.2.1",
            build: "12",
            date: "02/07/2026 00:00:00", // Sobrescrito dinamicamente pela data real do build
            changes: [
                "Funcionamento com a tela bloqueada: o comando Siri inicia a chamada via CallKit em background (sem exigir desbloqueio).",
                "Detecção de fim de fala movida para o run loop principal (confiável em background).",
                "Nome da chamada no CallKit atualizado para \"Hermes Voice\".",
                "App definido como iPhone-only e orientação retrato declarada (requisitos de bundle para TestFlight)."
            ],
            isCurrent: false
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
