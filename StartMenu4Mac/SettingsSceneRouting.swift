import Foundation

enum SettingsSceneOpenSequence {
    @MainActor
    static func perform(
        prepareForSettings: @MainActor @Sendable () -> Void,
        activateApplication: @MainActor @Sendable () -> Void,
        openSettings: @MainActor @Sendable () -> Void
    ) {
        prepareForSettings()
        activateApplication()
        openSettings()
    }
}
