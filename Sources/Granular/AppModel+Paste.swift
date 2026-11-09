import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Images that arrive without a file of their own: Edit ▸ Paste and
// File ▸ Import from iPhone or iPad.
extension AppModel {
    /// Pasteboard image types Granular reads as they are, best first.
    private static let pastedImageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(UTType.heic.identifier),
        .tiff
    ]

    /// Opens images in the mode that is showing: Edit mode opens the first and
    /// offers the rest to Instant mode, Instant mode develops them all.
    func openIncomingImages(_ urls: [URL]) {
        if operationMode == .edit {
            openForEditing(urls)
        } else {
            Task { await processInstantly(urls) }
        }
    }

    /// Image files copied in Finder. Reading them this way is what lets a
    /// sandboxed app open them.
    private func imageFiles(on pasteboard: NSPasteboard) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return nil }
        return urls.filter(Self.isSupportedImage)
    }

    func canPasteImage(from pasteboard: NSPasteboard = .general) -> Bool {
        // A copied file carries its icon as image data, so files are judged
        // as files alone.
        if let files = imageFiles(on: pasteboard) {
            return !files.isEmpty
        }
        return pasteboard.availableType(from: Self.pastedImageTypes) != nil
    }

    /// Opens the image on the pasteboard. False when there isn't one.
    @discardableResult
    func pasteImage(from pasteboard: NSPasteboard = .general) -> Bool {
        if let files = imageFiles(on: pasteboard) {
            guard !files.isEmpty else { return false }
            openIncomingImages(files)
            return true
        }
        guard let type = pasteboard.availableType(from: Self.pastedImageTypes),
              let data = pasteboard.data(forType: type) else { return false }
        return openImageData(data, named: "Pasted Image")
    }

    /// Writes image data to a temporary file and opens it. The file keeps the
    /// data's own encoding when Granular reads it, and becomes a PNG otherwise.
    @discardableResult
    func openImageData(_ data: Data, named name: String) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier) else { return false }

        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Granular", directoryHint: .isDirectory)
            .appending(path: "Pasted", directoryHint: .isDirectory)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stem = "\(name) \(formatter.string(from: .now))"

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url: URL
            if Self.supportedImageTypes.contains(type), let ext = type.preferredFilenameExtension {
                url = folder.appending(path: "\(stem).\(ext)")
                try data.write(to: url, options: .atomic)
            } else {
                url = folder.appending(path: "\(stem).png")
                guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      let destination = CGImageDestinationCreateWithURL(
                          url as CFURL, UTType.png.identifier as CFString, 1, nil
                      ) else { return false }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { return false }
            }
            openIncomingImages([url])
            return true
        } catch {
            editorAlert = EditorAlert(
                title: "Granular couldn’t open the image.",
                message: error.localizedDescription
            )
            return true
        }
    }

    /// Takes photos and scans from File ▸ Import from iPhone or iPad.
    func importImages(from providers: [NSItemProvider]) -> Bool {
        let images = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        guard !images.isEmpty else { return false }
        for provider in images {
            _ = provider.loadDataRepresentation(for: .image) { [weak self] data, _ in
                guard let data else { return }
                Task { @MainActor in
                    self?.openImageData(data, named: "Imported Image")
                }
            }
        }
        return true
    }
}

/// Answers Edit ▸ Paste for the main window when nothing nearer the focus
/// does. It sits at the end of the window's responder chain, so a text field
/// being edited still pastes text.
final class ImagePasteResponder: NSResponder, NSMenuItemValidation {
    weak var model: AppModel?
    weak var window: NSWindow?

    private var canPaste: Bool {
        // A sheet's own Paste would otherwise fall through to the window
        // beneath it.
        guard let model, window?.attachedSheet == nil else { return false }
        return model.canPasteImage()
    }

    @objc func paste(_ sender: Any?) {
        guard canPaste, model?.pasteImage() == true else {
            NSSound.beep()
            return
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(paste(_:)) ? canPaste : true
    }

    func attach(to window: NSWindow?) {
        guard window !== self.window else { return }
        if let old = self.window, old.nextResponder === self {
            old.nextResponder = nextResponder
        }
        nextResponder = nil
        self.window = window
        guard let window else { return }
        nextResponder = window.nextResponder
        window.nextResponder = self
    }
}

/// Puts an `ImagePasteResponder` on the window this view is in.
private struct ImagePasteInstaller: NSViewRepresentable {
    let model: AppModel

    final class HostView: NSView {
        let responder = ImagePasteResponder()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            responder.attach(to: window)
        }
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.responder.model = model
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        view.responder.model = model
    }
}

extension View {
    /// Edit ▸ Paste and File ▸ Import from iPhone or iPad open an image here.
    func receivingImages(for model: AppModel) -> some View {
        background { ImagePasteInstaller(model: model) }
            .importsItemProviders([.image]) { providers in
                model.importImages(from: providers)
            }
    }
}
