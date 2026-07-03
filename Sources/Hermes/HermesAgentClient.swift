import Foundation
import Combine

enum HermesConnectionState: String {
    case disconnected = "Desconectado"
    case connecting = "Conectando..."
    case connected = "Conectado"
}

protocol HermesAgentClientProtocol {
    var connectionStatePublisher: Published<HermesConnectionState>.Publisher { get }
    var currentConnectionState: HermesConnectionState { get }
    func connect() async throws
    func send(_ userText: String) -> AsyncThrowingStream<String, Error>
    func resetConversation() async
    func disconnect() async
}

/// Cliente do Hermes usando o API server OpenAI-compatível (`hermes gateway`, porta 8642).
///
/// Diferente do dashboard (WebSocket + PTY/ANSI + token de sessão), esta via é feita
/// para integrações programáticas: JSON limpo, streaming SSE e autenticação `Bearer`.
///
/// - Endpoint de chat: `POST {base}/v1/chat/completions` com `stream: true`
/// - Auth: `Authorization: Bearer <API_SERVER_KEY>`
/// - Continuidade da conversa: header `X-Hermes-Session-Id` (fixo por conversa)
/// - Health check: `GET {base}/health`
// @unchecked Sendable: singleton; estado de conexão publicado na main thread e
// requisições em Task controladas. Silencia avisos de captura em closures @Sendable.
class HermesAgentClient: NSObject, HermesAgentClientProtocol, @unchecked Sendable {
    static let shared = HermesAgentClient()

    @Published private(set) var connectionState: HermesConnectionState = .disconnected
    @Published var lastConnectionLog: String = ""

    var connectionStatePublisher: Published<HermesConnectionState>.Publisher { $connectionState }
    var lastConnectionLogPublisher: Published<String>.Publisher { $lastConnectionLog }
    var currentConnectionState: HermesConnectionState { connectionState }

    /// Identificador da conversa atual. Trocar o id inicia uma "nova conversa" no servidor.
    private var sessionId = UUID().uuidString

    /// Tarefa do turno em andamento (permite cancelamento em disconnect).
    private var activeTask: Task<Void, Never>?

    /// O campo `model` é cosmético; o modelo real é definido no servidor.
    private let modelName = "hermes-agent"

    private override init() {
        super.init()
    }

    private func appendLog(_ message: String) {
        print(message)
        DispatchQueue.main.async {
            self.lastConnectionLog += message + "\n"
            // Evita crescimento sem limite em chamadas longas.
            if self.lastConnectionLog.count > 8000 {
                self.lastConnectionLog = String(self.lastConnectionLog.suffix(6000))
            }
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    // MARK: - Construção da URL base

    /// Normaliza o valor de `hostUrl` para uma base HTTP(S) sem barra final.
    /// Aceita esquemas ws/wss legados e converte para http/https.
    private func baseURL() -> URL? {
        var raw = SettingsStore.shared.hostUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        if raw.hasPrefix("wss://") {
            raw = "https://" + raw.dropFirst("wss://".count)
        } else if raw.hasPrefix("ws://") {
            raw = "http://" + raw.dropFirst("ws://".count)
        } else if !raw.hasPrefix("http://") && !raw.hasPrefix("https://") {
            raw = "https://" + raw
        }

        while raw.hasSuffix("/") {
            raw.removeLast()
        }

        return URL(string: raw)
    }

    private func authorizedRequest(path: String) throws -> URLRequest {
        guard let base = baseURL(), let url = URL(string: base.absoluteString + path) else {
            throw NSError(domain: "HermesAgentClient", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "URL do servidor Hermes inválida."])
        }

        var request = URLRequest(url: url)
        let apiKey = SettingsStore.shared.apiKey
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(sessionId, forHTTPHeaderField: "X-Hermes-Session-Id")
        return request
    }

    // MARK: - Ciclo de vida

    func connect() async throws {
        await disconnect()

        DispatchQueue.main.async {
            self.lastConnectionLog = ""
            self.connectionState = .connecting
        }

        appendLog("--- HERMES API SERVER (OpenAI-compatível) ---")
        appendLog("Build: v\(VersionManager.shared.currentVersionString) — commit \(VersionManager.shared.currentCommit)")

        var request = try authorizedRequest(path: "/health")
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        appendLog("Health check: \(request.url?.absoluteString ?? "?")")
        appendLog("Session-Id: \(sessionId)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "HermesAgentClient", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Resposta inválida do servidor."])
            }
            appendLog("Status /health: \(http.statusCode)")

            // Alguns builds expõem /v1/health em vez de /health.
            if http.statusCode == 404 {
                appendLog("Tentando /v1/health...")
                var alt = try authorizedRequest(path: "/v1/health")
                alt.httpMethod = "GET"
                alt.timeoutInterval = 15
                let (_, altResponse) = try await URLSession.shared.data(for: alt)
                if let altHTTP = altResponse as? HTTPURLResponse {
                    appendLog("Status /v1/health: \(altHTTP.statusCode)")
                    guard (200...299).contains(altHTTP.statusCode) else {
                        throw httpError(altHTTP.statusCode, data: nil)
                    }
                }
            } else if !(200...299).contains(http.statusCode) {
                throw httpError(http.statusCode, data: data)
            }

            DispatchQueue.main.async {
                self.connectionState = .connected
            }
            appendLog("Conectado ao API server com sucesso.")
        } catch {
            appendLog("Falha ao conectar: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.connectionState = .disconnected
            }
            throw error
        }
    }

    func disconnect() async {
        activeTask?.cancel()
        activeTask = nil
        DispatchQueue.main.async {
            self.connectionState = .disconnected
        }
    }

    struct ModelInfo {
        let model: String
        let provider: String
    }

    /// Consulta o modelo e o motor (provider) LLM configurados no servidor, via a rota
    /// de diagnóstico `/admin/model-info` (nginx repassa para o dashboard do Hermes,
    /// autenticado pela mesma API Key — o app nunca vê a credencial do dashboard).
    func fetchModelInfo() async throws -> ModelInfo {
        var request = try authorizedRequest(path: "/admin/model-info")
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "HermesAgentClient", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "Não foi possível obter informações do modelo (HTTP \(code))."])
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? String, !model.isEmpty,
              let provider = json["provider"] as? String, !provider.isEmpty else {
            throw NSError(domain: "HermesAgentClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Resposta de modelo vazia ou inesperada."])
        }
        return ModelInfo(model: model, provider: provider)
    }

    func resetConversation() async {
        // Trocar o id de sessão faz o servidor tratar como uma nova conversa.
        sessionId = UUID().uuidString
        appendLog("Nova conversa iniciada (Session-Id: \(sessionId))")
    }

    // MARK: - Envio com streaming SSE

    func send(_ userText: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try authorizedRequest(path: "/v1/chat/completions")
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let payload: [String: Any] = [
                        "model": modelName,
                        "stream": true,
                        "messages": [
                            ["role": "user", "content": userText]
                        ]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

                    let preview = userText.count > 60 ? String(userText.prefix(60)) + "…" : userText
                    self.appendLog("→ [\(self.timestamp())] Enviando ao agente: \"\(preview)\"")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse,
                       !(200...299).contains(http.statusCode) {
                        // Corpo de erro costuma vir em uma única linha JSON.
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw self.httpError(http.statusCode, data: body.data(using: .utf8))
                    }

                    var receivedChars = 0
                    var firstToken = true

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        // Formato SSE: linhas começam com "data: ".
                        guard line.hasPrefix("data:") else { continue }
                        let jsonPart = line.dropFirst("data:".count)
                            .trimmingCharacters(in: .whitespaces)

                        if jsonPart == "[DONE]" {
                            break
                        }
                        guard let data = jsonPart.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }

                        // Registra ferramentas que o agente está executando (se o servidor as expõe).
                        for tool in Self.extractToolNames(from: obj) {
                            self.appendLog("🔧 [\(self.timestamp())] Executando ferramenta: \(tool)")
                        }

                        if let delta = Self.extractDelta(from: obj), !delta.isEmpty {
                            if firstToken {
                                firstToken = false
                                self.appendLog("← [\(self.timestamp())] Agente respondendo…")
                            }
                            receivedChars += delta.count
                            continuation.yield(delta)
                        }
                    }

                    self.appendLog("✓ [\(self.timestamp())] Turno concluído (\(receivedChars) caracteres)")
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        self.appendLog("✗ [\(self.timestamp())] Erro no turno: \(error.localizedDescription)")
                    }
                    continuation.finish(throwing: error)
                }
            }

            self.activeTask = task
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Helpers

    /// Extrai o texto incremental de um chunk do Chat Completions.
    /// `choices[0].delta.content` (streaming) com fallback para `choices[0].message.content`.
    private static func extractDelta(from obj: [String: Any]) -> String? {
        guard let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first else {
            return nil
        }
        if let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return content
        }
        if let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        return nil
    }

    /// Extrai nomes de ferramentas invocadas no chunk (`choices[0].delta.tool_calls[].function.name`),
    /// caso o servidor exponha a execução do agente no stream OpenAI-compatível.
    private static func extractToolNames(from obj: [String: Any]) -> [String] {
        guard let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let toolCalls = delta["tool_calls"] as? [[String: Any]] else {
            return []
        }
        return toolCalls.compactMap { call in
            (call["function"] as? [String: Any])?["name"] as? String
        }.filter { !$0.isEmpty }
    }

    private func httpError(_ statusCode: Int, data: Data?) -> NSError {
        var detail = "Servidor retornou HTTP \(statusCode)."
        switch statusCode {
        case 401, 403:
            detail = "Autenticação recusada (HTTP \(statusCode)). Verifique a API Key (Bearer)."
        case 404:
            detail = "Endpoint não encontrado (HTTP 404). Confirme a URL base do API server."
        default:
            break
        }
        if let data = data, let body = String(data: data, encoding: .utf8), !body.isEmpty {
            detail += " \(body.prefix(300))"
        }
        return NSError(domain: "HermesAgentClient", code: statusCode,
                       userInfo: [NSLocalizedDescriptionKey: detail])
    }
}
