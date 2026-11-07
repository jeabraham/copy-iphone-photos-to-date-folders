import Foundation

// Wire format shared with copy-iphone-photos.swift:
// [UInt32 big-endian payload length][UInt8 kind][payload]. Kind 0 = JSON, 1 = file data.
enum FrameKind: UInt8 {
    case json = 0
    case data = 1
}

struct SocketError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class FrameSocket {
    static let maxFrame = 64 * 1024 * 1024
    let descriptor: Int32

    init(descriptor: Int32) {
        self.descriptor = descriptor
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { close(descriptor) }

    private func writeAll(_ bytes: UnsafeRawBufferPointer) throws {
        var offset = 0
        while offset < bytes.count {
            let written = send(descriptor, bytes.baseAddress! + offset, bytes.count - offset, 0)
            if written < 0 && errno == EINTR { continue }
            guard written > 0 else { throw SocketError(message: "Mac connection closed while sending") }
            offset += written
        }
    }

    private func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { buffer in
            while offset < count {
                let received = recv(descriptor, buffer.baseAddress! + offset, count - offset, 0)
                if received < 0 && errno == EINTR { continue }
                guard received > 0 else { throw SocketError(message: "Mac connection closed") }
                offset += received
            }
        }
        return data
    }

    func sendFrame(_ kind: FrameKind, _ payload: Data) throws {
        var header = Data(count: 5)
        let length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: length) { header.replaceSubrange(0..<4, with: $0) }
        header[4] = kind.rawValue
        try header.withUnsafeBytes(writeAll)
        try payload.withUnsafeBytes(writeAll)
    }

    func sendJSON(_ object: [String: Any]) throws {
        try sendFrame(.json, JSONSerialization.data(withJSONObject: object))
    }

    func readRequest() throws -> [String: Any] {
        let header = try readExactly(5)
        let length = Int(header.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        guard header[4] == FrameKind.json.rawValue, length <= Self.maxFrame else {
            throw SocketError(message: "Invalid request frame")
        }
        let payload = try readExactly(length)
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw SocketError(message: "Request is not a JSON object")
        }
        return object
    }
}
