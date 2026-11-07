import Foundation
import Photos
import UIKit

// Serves one Mac client at a time. It binds to loopback only: usbmuxd delivers
// USB connections to 127.0.0.1 on the phone, so Wi-Fi peers cannot reach it.
final class CompanionServer: @unchecked Sendable {
    static let port: UInt16 = 58214
    private let report: @Sendable (String) -> Void

    init(report: @escaping @Sendable (String) -> Void) { self.report = report }

    func start() throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw SocketError(message: "Cannot create socket") }
        var on: Int32 = 1
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = Self.port.bigEndian
        address.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(listener, 1) == 0 else {
            close(listener)
            throw SocketError(message: "Cannot listen on port \(Self.port): \(String(cString: strerror(errno)))")
        }
        let thread = Thread { [self] in
            while true {
                let client = accept(listener, nil, nil)
                if client < 0 { if errno == EINTR { continue } else { break } }
                serve(FrameSocket(descriptor: client))
            }
        }
        thread.name = "companion-accept"
        thread.start()
    }

    private func serve(_ connection: FrameSocket) {
        report("Mac connected")
        do {
            while true {
                let request = try connection.readRequest()
                switch request["op"] as? String {
                case "hello": try hello(connection)
                case "list": try list(request, connection)
                case "fetch": try fetch(request, connection)
                default: try connection.sendJSON(["ok": false, "error": "Unknown operation"])
                }
            }
        } catch {
            report("Mac disconnected")
        }
    }

    private func hello(_ connection: FrameSocket) throws {
        let name = DispatchQueue.main.sync { UIDevice.current.name }
        try connection.sendJSON(["ok": true, "protocol": 1, "name": name,
                                 "authorized": isAuthorized])
    }

    private var isAuthorized: Bool { PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized }

    private func list(_ request: [String: Any], _ connection: FrameSocket) throws {
        guard isAuthorized else {
            try connection.sendJSON(["ok": false, "error": "Grant full Photos access to the companion app"])
            return
        }
        let from = (request["from"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let to = (request["to"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let assets = PhotoLibrary.list(from: from, to: to, excludeMovies: request["excludeMovies"] as? Bool ?? false)
        report("Listed \(assets.count) assets")
        try connection.sendJSON(["ok": true, "assets": assets])
    }

    private func fetch(_ request: [String: Any], _ connection: FrameSocket) throws {
        guard isAuthorized, let id = request["id"] as? String, let type = request["type"] as? String,
              let name = request["name"] as? String,
              let resource = PhotoLibrary.resource(assetID: id, type: type, name: name) else {
            try connection.sendJSON(["ok": false, "error": "Asset resource not found or access not granted"])
            return
        }
        report("Sending \(name)…")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        options.progressHandler = { [report] progress in
            report("Downloading \(name) from iCloud: \(Int(progress * 100))%")
        }
        let done = DispatchSemaphore(value: 0)
        var failure: Error?
        var total = 0
        // The data handler blocks on the socket, which gives the Mac backpressure over the phone.
        PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { data in
            guard failure == nil else { return }
            do {
                try connection.sendFrame(.data, data)
                total += data.count
            } catch { failure = error }
        }, completionHandler: { error in
            if failure == nil { failure = error }
            done.signal()
        })
        done.wait()
        if let failure = failure as? SocketError { throw failure }
        if let failure = failure {
            try connection.sendJSON(["ok": false, "error": failure.localizedDescription])
        } else {
            try connection.sendJSON(["ok": true, "bytes": total])
            report("Sent \(name) (\(total) bytes)")
        }
    }
}
