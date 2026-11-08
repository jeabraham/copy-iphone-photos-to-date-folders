import Foundation
import OSLog

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

// Runs one import at a time and exposes its output for the modal status sheet.
@MainActor
final class ImportRunner: ObservableObject {
    @Published private(set) var lines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var exitCode: Int32?
    @Published private(set) var isCancelling = false

    private let logger = Logger(subsystem: "com.jeabraham.PhotoImporter", category: "Import")
    private var importID = UUID()
    private var cancelFlag = CancelFlag()
    private var directImporter: Importer?
    private weak var phoneDetector: PhoneDetector?

    func start(_ job: ImportJob, detector: PhoneDetector) {
        guard !isRunning else { return }
        lines = []
        exitCode = nil
        isCancelling = false
        isRunning = true
        cancelFlag = CancelFlag()
        let flag = cancelFlag
        importID = UUID()
        append("Starting \(job.mode) import from \(job.source.label) to \(job.destination.path). Dry run: \(job.settings.dryRun); redownload deleted: \(job.settings.redownloadDeletedFiles)")

        // The importer's globals are process-wide; output may arrive from a worker thread.
        importerOutputSink = { [weak self] text in DispatchQueue.main.async { self?.append(text) } }
        importerErrorSink = { [weak self] text in DispatchQueue.main.async { self?.append(text) } }
        importerCancelled = { flag.isSet }

        switch job.mode {
        case .card:
            Task.detached {
                let code = CardImporter.run(job: job, isCancelled: { flag.isSet },
                                            log: { text in DispatchQueue.main.async { self.append(text) } })
                await self.finish(code)
            }
        case .phoneViaApp:
            Task.detached {
                let code: Int32
                do {
                    code = CompanionImporter(options: try job.importerOptions()).run()
                } catch {
                    DispatchQueue.main.async { self.append(error.localizedDescription) }
                    code = 1
                }
                await self.finish(code)
            }
        case .phoneDirect:
            do {
                // ImageCaptureCore delivers delegate callbacks on the main run loop, so this runs here.
                let importer = Importer(options: try job.importerOptions())
                importer.onFinish = { [weak self] code in
                    DispatchQueue.main.async { self?.finish(code) }
                }
                directImporter = importer
                append("Looking for “\(job.source.location)”…")
                phoneDetector = detector
                detector.beginImport(importer)
                remindIfSilent()
            } catch {
                append(error.localizedDescription)
                finish(1)
            }
        }
    }

    private func remindIfSilent() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            if isRunning, lines.count <= 2 {
                append("Still waiting for the iPhone. Unlock it, tap Trust, and close Image Capture, Photos and Lightroom import windows. The import gives up after \(Int(Options().timeout)) seconds.")
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        isCancelling = true
        cancelFlag.set()
        directImporter?.cancel()
    }

    private func append(_ text: String) {
        lines.append(text)
        logger.notice("[\(self.importID.uuidString, privacy: .public)] \(text, privacy: .public)")
    }

    private func finish(_ code: Int32) {
        guard isRunning else { return }
        append("Import finished with exit code \(code).")
        phoneDetector?.endImport()
        phoneDetector = nil
        directImporter = nil
        exitCode = code
        isRunning = false
        isCancelling = false
    }
}
