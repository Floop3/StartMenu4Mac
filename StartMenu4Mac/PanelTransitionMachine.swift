import Foundation

struct PanelTransitionMachine {
    enum State: Equatable {
        case hidden
        case opening
        case visible
        case closing
    }

    enum HideRequest: Equatable {
        case alreadyHidden(shouldHideApplication: Bool)
        case mergeExisting
        case started(generation: Int)
    }

    enum HideIntentPolicy {
        case merge
        case replace
    }

    private(set) var state: State = .hidden
    private(set) var generation = 0
    private var shouldHideApplicationAfterClosing = false

    mutating func beginShowing() -> Int? {
        guard state == .hidden else { return nil }
        generation += 1
        state = .opening
        return generation
    }

    mutating func finishShowing(generation: Int) -> Bool {
        guard self.generation == generation, state == .opening else { return false }
        state = .visible
        return true
    }

    mutating func beginHiding(
        alsoHideApplication: Bool,
        intentPolicy: HideIntentPolicy = .merge
    ) -> HideRequest {
        switch state {
        case .hidden:
            return .alreadyHidden(shouldHideApplication: alsoHideApplication)
        case .closing:
            switch intentPolicy {
            case .merge:
                shouldHideApplicationAfterClosing = shouldHideApplicationAfterClosing || alsoHideApplication
            case .replace:
                shouldHideApplicationAfterClosing = alsoHideApplication
            }
            return .mergeExisting
        case .opening, .visible:
            generation += 1
            state = .closing
            shouldHideApplicationAfterClosing = alsoHideApplication
            return .started(generation: generation)
        }
    }

    mutating func finishHiding(generation: Int) -> Bool? {
        guard self.generation == generation, state == .closing else { return nil }
        state = .hidden
        let shouldHideApplication = shouldHideApplicationAfterClosing
        shouldHideApplicationAfterClosing = false
        return shouldHideApplication
    }
}

enum PanelLaunchOrdering {
    static func launchThenClose(launch: () -> Void, close: () -> Void) {
        launch()
        close()
    }
}
