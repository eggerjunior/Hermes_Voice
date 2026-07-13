import ActivityKit
import Foundation

enum HermesLiveActivityController {
    private static var currentActivity: Activity<HermesLiveActivityAttributes>?

    static var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    @discardableResult
    static func start(status: String, prompt: String, response: String) -> Bool {
        guard activitiesEnabled else { return false }

        let attributes = HermesLiveActivityAttributes(sessionName: "Hermes Voice")
        let state = HermesLiveActivityAttributes.ContentState(
            status: status,
            prompt: prompt,
            response: response,
            updatedAt: Date()
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            return true
        } catch {
            return false
        }
    }

    static func update(status: String, prompt: String, response: String) async {
        guard let activity = currentActivity ?? Activity<HermesLiveActivityAttributes>.activities.first else {
            return
        }

        let state = HermesLiveActivityAttributes.ContentState(
            status: status,
            prompt: prompt,
            response: response,
            updatedAt: Date()
        )
        await activity.update(.init(state: state, staleDate: nil))
    }

    static func end() async {
        guard let activity = currentActivity ?? Activity<HermesLiveActivityAttributes>.activities.first else {
            return
        }

        let finalState = activity.content.state
        await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        currentActivity = nil
    }
}
