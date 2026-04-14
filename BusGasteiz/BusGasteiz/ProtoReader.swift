import Foundation

// MARK: - Lector de Protocol Buffers (wire format manual)

struct ProtoReader: Sendable {
    let data: Data
    var position: Int = 0

    nonisolated init(data: Data) { self.data = data }

    nonisolated mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0; var shift: UInt64 = 0
        while position < data.count {
            let byte = data[position]; position += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7; if shift >= 64 { return nil }
        }
        return nil
    }

    nonisolated mutating func readLengthDelimited() -> Data? {
        guard let length = readVarint() else { return nil }
        guard length <= UInt64(Int.max) else { return nil }
        let len = Int(length)
        guard position + len <= data.count else { return nil }
        let result = Data(data[position..<(position + len)])
        position += len; return result
    }

    nonisolated mutating func readTag() -> (field: Int, wire: Int)? {
        guard let tag = readVarint() else { return nil }
        return (Int(truncatingIfNeeded: tag >> 3), Int(truncatingIfNeeded: tag & 0x7))
    }

    nonisolated mutating func skip(wire: Int) {
        switch wire {
        case 0: _ = readVarint()
        case 1: position = min(position + 8, data.count)
        case 2: _ = readLengthDelimited()
        case 5: position = min(position + 4, data.count)
        default: position = data.count
        }
    }

    nonisolated var hasMore: Bool { position < data.count }
}
