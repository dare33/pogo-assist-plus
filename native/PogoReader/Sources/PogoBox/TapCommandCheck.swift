import Foundation

/// A tap command holds absolute screen points, so it is only safe on the screen it was made for, and the app cannot see what is installed in
/// Voice Control. It knows what it made and for which screen, so every tap command it made is checked against the current screen whatever
/// pace is selected: Display Zoom, or a restore onto another phone, can leave an installed command that is unsafe here.
public enum TapCommandCheck {
    /// The tap paces whose last command was made for a screen other than `current`, or for a screen that was not recorded. `made` is each
    /// pace with a record and the screen label it recorded. Swipe paces never appear: a swipe does not press anything.
    public static func onOtherScreens(made: [(pace: VoiceCommandFile.Pace, screen: String?)], current: String) -> [VoiceCommandFile.Pace] {
        let unsafe = made.filter { $0.pace.isTap && $0.screen != current }.map { $0.pace }
        return VoiceCommandFile.Pace.allCases.filter { unsafe.contains($0) }   // a fixed order, however the records were listed
    }

    /// The same check over the records of EVERY account on the device. Voice Control's commands are device-wide and share their names
    /// ("Pogo scan"), so a record under another account says what may be installed just as one under the selected account does. If any
    /// account's record of a tap pace is for another screen, that command is flagged: which import is the installed one cannot be known.
    public static func onOtherScreens(accounts: [String: [(pace: VoiceCommandFile.Pace, screen: String?)]], current: String) -> [VoiceCommandFile.Pace] {
        onOtherScreens(made: accounts.values.flatMap { $0 }, current: current)
    }

    /// What the Scan screen says, or nil when nothing is unsafe. Names every command, says not to say them here and where to delete them.
    public static func warning(for paces: [VoiceCommandFile.Pace]) -> String? {
        guard !paces.isEmpty else { return nil }
        let names = paces.map { "\"\($0.commandName)\"" }
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
        let these = paces.count == 1 ? "This command was" : "These commands were"
        let them = paces.count == 1 ? "it" : "them"
        return "\(these) made for another screen: \(list). Do not say \(them) on this screen: the taps are placed for the other screen and can press a button in the game. Delete \(them) in Settings > Accessibility > Voice Control > Commands, then make the command again here."
    }
}
