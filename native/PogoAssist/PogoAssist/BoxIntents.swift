import AppIntents
import UniformTypeIdentifiers
import PogoBox
import PogoReader

/// The same two choices as the Box screen's export.
extension ExportFormat: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Format" }
    static var caseDisplayRepresentations: [ExportFormat: DisplayRepresentation] { [.csv: "CSV", .markdown: "For Claude or ChatGPT"] }
}

/// Shortcuts shows an error's own words only through this.
extension BoxExportFile.Failure: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: errorDescription ?? "The box could not be exported.") }
}

/// The account names for the Shortcuts action's picker.
struct AccountOptions: DynamicOptionsProvider {
    func results() async throws -> [String] { (try? BoxLibrary(root: BoxExportFile.boxesRoot).accounts()) ?? [] }
}

/// "Get Pokémon box": the saved box as a file a Shortcut can hand to the ChatGPT or Claude app. Read-only: it opens no scan, no broadcast and no screen.
struct GetPokemonBoxIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Pokémon box"
    static var description = IntentDescription("Returns your saved Pokémon box as a file, for example to give to ChatGPT or Claude.", categoryName: "Box")
    static var openAppWhenRun = false

    @Parameter(title: "Account", description: "The account whose box to export. Leave empty for the one selected in the app.", optionsProvider: AccountOptions())
    var account: String?

    @Parameter(title: "Format", default: .markdown)
    var format: ExportFormat

    static var parameterSummary: some ParameterSummary { Summary("Get the \(\.$format) box of \(\.$account)") }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let library = BoxLibrary(root: BoxExportFile.boxesRoot)
        guard let name = account ?? BoxExportFile.defaultAccount(in: library) else { throw BoxExportFile.Failure.noAccount }
        if let n = library.newerVersion(account: name) { throw BoxExportFile.Failure.unreadable("The box for \(name) was saved by a newer version of the app (version \(n)). Update Pogo Assist+.") }
        let snap: BoxSnapshot
        do { guard let s = try library.current(account: name), !s.entries.isEmpty else { throw BoxExportFile.Failure.noBox(name) }; snap = s }
        catch let f as BoxExportFile.Failure { throw f }
        catch { throw BoxExportFile.Failure.unreadable("The box for \(name) could not be read: \(error.localizedDescription)") }
        let format = format
        let url = try await EngineWorker().run { engine in try BoxExportFile.write(format, snap: snap, library: library, engine: engine) }
        let type: UTType = format == .csv ? .commaSeparatedText : (UTType(filenameExtension: "md") ?? .plainText)
        return .result(value: IntentFile(fileURL: url, filename: url.lastPathComponent, type: type))
    }
}

struct PogoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetPokemonBoxIntent(), phrases: ["Get my Pokémon box in \(.applicationName)", "Export my box from \(.applicationName)"],
                    shortTitle: "Get Pokémon box", systemImageName: "square.and.arrow.up")
    }
}
