import ActivityKit
import Foundation

struct HermesLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: String
        var prompt: String
        var response: String
        var updatedAt: Date

        static let preview = ContentState(
            status: "Ouvindo",
            prompt: "Conversa ativa no carro.",
            response: "Hermes pronto para responder por voz.",
            updatedAt: Date()
        )
    }

    var sessionName: String

    static let preview = HermesLiveActivityAttributes(sessionName: "Hermes Voice")
}
