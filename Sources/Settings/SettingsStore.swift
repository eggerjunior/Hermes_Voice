import Foundation
import Combine

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    
    @Published var hostUrl: String {
        didSet {
            UserDefaults.standard.set(hostUrl, forKey: "hermes_host_url")
        }
    }
    
    @Published var ttsRate: Float {
        didSet {
            UserDefaults.standard.set(ttsRate, forKey: "hermes_tts_rate")
        }
    }
    
    @Published var sttLanguage: String {
        didSet {
            UserDefaults.standard.set(sttLanguage, forKey: "hermes_stt_language")
        }
    }
    
    /// Chave do API server OpenAI-compatível (`API_SERVER_KEY`), enviada como `Bearer`.
    /// Armazenada com segurança no Keychain.
    @Published var apiKey: String {
        didSet {
            KeychainStore.shared.save(key: "hermes_api_key", value: apiKey)
        }
    }

    private init() {
        self.hostUrl = UserDefaults.standard.string(forKey: "hermes_host_url") ?? "https://api.egger.app.br"
        self.ttsRate = UserDefaults.standard.object(forKey: "hermes_tts_rate") as? Float ?? 0.5
        self.sttLanguage = UserDefaults.standard.string(forKey: "hermes_stt_language") ?? "pt-BR"
        // Migração: reaproveita a senha legada (Basic Auth) como API Key, se existir.
        self.apiKey = KeychainStore.shared.get(key: "hermes_api_key")
            ?? KeychainStore.shared.get(key: "hermes_pass")
            ?? ""
    }
}
