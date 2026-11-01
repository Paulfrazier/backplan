import AppIntents
import Foundation

/// Done / Running late / Start school morning, as App Intents.
///
/// All three are `LiveActivityIntent`s, and that conformance is load-bearing,
/// not decoration: it is what makes the system run `perform()` in the *app's*
/// process (launching it in the background if need be) rather than in the
/// widget extension, which can't see `TimerController` and could only scribble
/// on a copy of the chain the app would then contradict. A plain `AppIntent`
/// button on a widget runs in the extension.
///
/// They live in `ios/Shared` so both targets compile them — the widget needs
/// the types to build `Button(intent:)`, the app needs them to run — and
/// `perform()` hands off to `IntentRouter.handler`, which only the app installs
/// (`BackplanApp.init`). In the extension it stays nil, so a stray in-process
/// run does nothing rather than something wrong.
enum IntentAction: Sendable, Equatable {
    case done
    case late(Int)
    case startMorning
}

@MainActor
enum IntentRouter {
    /// Returns the sentence Siri / Shortcuts says back.
    static var handler: ((IntentAction) async -> String)?

    static func run(_ action: IntentAction) async -> String {
        guard let handler else { return "Open Backplan to do that." }
        return await handler(action)
    }
}

struct FinishStepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Done with this step"
    static let description = IntentDescription("Finish the running step now; the rest of its run moves up.")
    static let openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await IntentRouter.run(.done)))
    }
}

struct RunningLateIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "I'm running late"
    static let description = IntentDescription("Push the running step (or the next one) later. The target never moves.")
    static let openAppWhenRun = false

    @Parameter(title: "Minutes", default: 5, inclusiveRange: (1, 60))
    var minutes: Int

    init() {}
    init(minutes: Int) { self.minutes = minutes }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await IntentRouter.run(.late(minutes))))
    }
}

/// A `LiveActivityIntent` too: arming starts the Live Activity, and only this
/// conformance lets a background launch request one.
struct StartMorningIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start school morning"
    static let description = IntentDescription("Arm tomorrow morning's plan and start the countdown.")
    static let openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await IntentRouter.run(.startMorning)))
    }
}
