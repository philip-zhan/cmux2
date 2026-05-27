import Foundation

extension RightSidebarMode {
    static func from(cliArgument rawValue: String) -> RightSidebarMode? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "files":
            return .files
        case "find":
            return .find
        case "sourcecontrol", "source-control", "git", "scm":
            return .sourceControl
        case "vault", "sessions":
            return .sessions
        case "feed":
            return .feed
        case "dock":
            return .dock
        case "history":
            return .history
        default:
            return nil
        }
    }

    static func availableModes(defaults: UserDefaults = .standard) -> [RightSidebarMode] {
        availableModes(
            dockEnabled: RightSidebarBetaFeatureSettings.isDockEnabled(defaults: defaults),
            defaults: defaults
        )
    }

    static func availableModes(dockEnabled: Bool, defaults: UserDefaults = .standard) -> [RightSidebarMode] {
        allCases.filter { $0.isAvailable(dockEnabled: dockEnabled, defaults: defaults) }
    }

    func isAvailable(defaults: UserDefaults = .standard) -> Bool {
        isAvailable(
            dockEnabled: RightSidebarBetaFeatureSettings.isDockEnabled(defaults: defaults),
            defaults: defaults
        )
    }

    func isAvailable(dockEnabled: Bool, defaults: UserDefaults = .standard) -> Bool {
        guard isEnabledByBetaGate(dockEnabled: dockEnabled) else { return false }
        return RightSidebarTabVisibilitySettings.isVisible(self, defaults: defaults)
    }

    /// Whether the tab is unlocked by beta flags, ignoring user visibility.
    private func isEnabledByBetaGate(dockEnabled: Bool) -> Bool {
        switch self {
        case .files, .find, .sourceControl, .sessions, .feed:
            return true
        case .dock:
            return dockEnabled
        case .history:
            return true
        }
    }
}
