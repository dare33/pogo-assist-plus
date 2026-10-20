import UIKit
import UniformTypeIdentifiers
import PogoImport

/// The Share extension: "Share, then Pogo Assist+" from Photos. It does the one thing an extension can be trusted to finish in the short time it has: copy the screenshots into
/// the app group's queue (upright, metadata removed, hashed) and write the batch's manifest. It reads nothing, runs no Vision and links no reader or box code, so it stays well
/// under an extension's memory limit. Reading starts by itself the next time the person opens Pogo Assist+, which this screen says. It never tries to open the app.
final class ShareViewController: UIViewController {
    private let spinner = UIActivityIndicatorView(style: .large)
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private var failed = false

    private var groupID: String { (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "group.com.dare33.pogoassist" }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        titleLabel.font = .preferredFont(forTextStyle: .title3)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.text = "Adding screenshots…"
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.textAlignment = .center
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [spinner, titleLabel, detailLabel, doneButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -12),
        ])
        spinner.startAnimating()
        Task { await stage() }
    }

    @objc private func finish() {
        if failed { extensionContext?.cancelRequest(withError: NSError(domain: "PogoShare", code: 1)) } else { extensionContext?.completeRequest(returningItems: nil) }
    }

    private func show(_ title: String, _ detail: String, failed: Bool = false) {
        self.failed = failed
        spinner.stopAnimating()
        titleLabel.text = title
        detailLabel.text = detail
        doneButton.isHidden = false
    }

    // MARK: staging

    private func stage() async {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return show("Could not add the screenshots", "Pogo Assist+ cannot be reached from here (its shared storage is not set up on this build). Open Pogo Assist+ and choose the screenshots there.", failed: true)
        }
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        guard !providers.isEmpty else {
            return show("No screenshots to add", "Choose screenshots of a Pokémon's appraisal screen in Photos, then share them to Pogo Assist+.", failed: true)
        }
        // The account the app has selected (it writes it to the group's defaults whenever it changes). A batch belongs to it from now on, whatever is selected later.
        let account = UserDefaults(suiteName: groupID)?.string(forKey: ImportQueue.selectedAccountKey)
        let queue = ImportQueue(container: container)
        let builder: ImportQueue.Builder
        do { builder = try queue.beginBatch(origin: .shareExtension, account: account) } catch {
            return show("Could not add the screenshots", "The phone could not make room for them (\(error.localizedDescription)).", failed: true)
        }
        var unusable = 0, tooMany = 0
        for provider in providers {
            if builder.items.count >= ImportQueue.maxImagesPerBatch { tooMany += 1; continue }
            if await Self.stage(provider, into: builder) { continue }
            unusable += 1
        }
        do {
            let batch = try builder.commit()
            var detail = "\(batch.items.count == 1 ? "It is" : "They are") queued and will be read the next time you open Pogo Assist+, then shown for you to check before anything is saved."
            detail += account.map { "\n\nFor the box of \($0)." } ?? "\n\nChoose an account in Pogo Assist+ for them."
            if unusable > 0 { detail += "\n\n\(unusable) \(unusable == 1 ? "picture" : "pictures") could not be used." }
            if tooMany > 0 { detail += "\n\n\(tooMany) more than the \(ImportQueue.maxImagesPerBatch) a batch can hold \(tooMany == 1 ? "was" : "were") left out." }
            show("\(batch.items.count) screenshot\(batch.items.count == 1 ? "" : "s") queued", detail)
        } catch {
            builder.abort()
            show("Could not add the screenshots", (error as? LocalizedError)?.errorDescription ?? "None of the pictures could be used.", failed: true)
        }
    }

    /// Stage one attachment. The file the system hands over is deleted when the handler returns, so it is copied inside it.
    private static func stage(_ provider: NSItemProvider, into builder: ImportQueue.Builder) async -> Bool {
        await withCheckedContinuation { cont in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url else { return cont.resume(returning: false) }
                cont.resume(returning: (try? builder.add(contentsOf: url)) != nil)
            }
        }
    }
}
