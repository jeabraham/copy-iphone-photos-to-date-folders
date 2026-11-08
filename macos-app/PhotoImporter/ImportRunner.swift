import Foundation

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

    private var cancelFlag = CancelFlag()
    private var directImporter: Importer?

    func start(_ job: ImportJob) {
        lines = []
        exitCode = nil
        isCancelling = false
        isRunning = true
        cancelFlag = CancelFlag()
        let flag = cancelFlag

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
                importer.start()
            } catch {
                append(error.localizedDescription)
                finish(1)
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
    }

    private func finish(_ code: Int32) {
        guard isRunning else { return }
        directImporter = nil
        exitCode = code
        isRunning = false
        isCancelling = false
    }
}
