import Foundation
import Compression

// MARK: - Extractor ZIP mínimo

enum ZIPExtractorError: Error, LocalizedError {
    case invalidSignature
    case unsupportedCompressionMethod(UInt16)
    case decompressionFailed
    case truncatedEntry(String)

    var errorDescription: String? {
        switch self {
        case .invalidSignature:                 return "Formato ZIP no válido"
        case .unsupportedCompressionMethod(let m): return "Método de compresión no soportado: \(m)"
        case .decompressionFailed:              return "Error al descomprimir entrada ZIP"
        case .truncatedEntry(let name):         return "Entrada truncada: \(name)"
        }
    }
}

struct ZIPExtractor {

    /// Extrae todos los archivos del ZIP (en memoria) al directorio `directory`.
    nonisolated static func extract(zipData: Data, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var offset = 0

        while offset + 30 <= zipData.count {
            let sig = zipData.readUInt32LE(at: offset)

            // Firma de cabecera local: PK\x03\x04
            guard sig == 0x04034b50 else { break }

            let flags             = zipData.readUInt16LE(at: offset + 6)
            let compressionMethod = zipData.readUInt16LE(at: offset + 8)
            var compressedSize    = Int(zipData.readUInt32LE(at: offset + 18))
            let uncompressedSize  = Int(zipData.readUInt32LE(at: offset + 22))
            let fileNameLength    = Int(zipData.readUInt16LE(at: offset + 26))
            let extraFieldLength  = Int(zipData.readUInt16LE(at: offset + 28))

            let headerSize = 30 + fileNameLength + extraFieldLength
            guard offset + headerSize <= zipData.count else { break }

            let fileNameData = zipData[offset + 30 ..< offset + 30 + fileNameLength]
            let fileName = String(data: fileNameData, encoding: .utf8)
                        ?? String(data: fileNameData, encoding: .isoLatin1)
                        ?? ""

            let dataOffset = offset + headerSize

            // Bit 3 de flags: sizes en cabecera local pueden ser 0; están tras los datos.
            // En ese caso saltamos la entrada (no es habitual en ZIPs estáticos de GTFS).
            let hasDataDescriptor = (flags & 0x08) != 0
            if hasDataDescriptor && compressedSize == 0 {
                offset = dataOffset
                continue
            }

            guard dataOffset + compressedSize <= zipData.count else {
                throw ZIPExtractorError.truncatedEntry(fileName)
            }

            if !fileName.isEmpty && !fileName.hasSuffix("/") {
                let compressedData = zipData[dataOffset ..< dataOffset + compressedSize]
                let fileURL = directory.appendingPathComponent(fileName)
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                switch compressionMethod {
                case 0:  // Stored
                    try Data(compressedData).write(to: fileURL)

                case 8:  // Deflate
                    let decompressed = try deflateDecompress(
                        data: Data(compressedData),
                        uncompressedSize: uncompressedSize
                    )
                    try decompressed.write(to: fileURL)

                default:
                    throw ZIPExtractorError.unsupportedCompressionMethod(compressionMethod)
                }
            }

            offset = dataOffset + compressedSize
        }
    }

    // MARK: - Descompresión DEFLATE

    private nonisolated static func deflateDecompress(data: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }

        // Doble de espacio como margen de seguridad
        let bufferSize = max(uncompressedSize + 1024, data.count * 2)
        var result = Data(count: bufferSize)

        let decompressedSize: Int = result.withUnsafeMutableBytes { destPtr in
            data.withUnsafeBytes { srcPtr in
                compression_decode_buffer(
                    destPtr.bindMemory(to: UInt8.self).baseAddress!,
                    bufferSize,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_DEFLATE
                )
            }
        }

        guard decompressedSize > 0 else { throw ZIPExtractorError.decompressionFailed }
        result.count = decompressedSize
        return result
    }
}

// MARK: - Extensiones de lectura en little-endian

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 3 < count else { return 0 }
        return UInt32(self[offset])
             | (UInt32(self[offset + 1]) << 8)
             | (UInt32(self[offset + 2]) << 16)
             | (UInt32(self[offset + 3]) << 24)
    }
}
