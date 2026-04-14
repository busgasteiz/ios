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

    // Entrada del directorio central (tamaños fiables aunque haya data descriptors)
    private struct CentralDirEntry {
        let fileName: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// Extrae todos los archivos del ZIP (en memoria) al directorio `directory`.
    /// Usa el directorio central del ZIP para obtener tamaños reales, lo que funciona
    /// correctamente con ZIPs que usan data descriptors (flag bit 3).
    nonisolated static func extract(zipData: Data, to directory: URL) throws {
        let entries = try parseCentralDirectory(zipData: zipData)
        print("[ZIPExtractor] \(entries.count) entradas en el directorio central")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for entry in entries {
            guard !entry.fileName.isEmpty, !entry.fileName.hasSuffix("/") else { continue }

            let localOffset = entry.localHeaderOffset
            guard localOffset + 30 <= zipData.count,
                  zipData.readUInt32LE(at: localOffset) == 0x04034b50 else { continue }

            let localFnLen    = Int(zipData.readUInt16LE(at: localOffset + 26))
            let localExtraLen = Int(zipData.readUInt16LE(at: localOffset + 28))
            let dataStart     = localOffset + 30 + localFnLen + localExtraLen

            guard dataStart + entry.compressedSize <= zipData.count else {
                throw ZIPExtractorError.truncatedEntry(entry.fileName)
            }

            let compressedData = zipData[dataStart ..< dataStart + entry.compressedSize]
            let fileURL = directory.appendingPathComponent(entry.fileName)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            switch entry.compressionMethod {
            case 0:  // Stored
                try Data(compressedData).write(to: fileURL)
            case 8:  // Deflate
                let decompressed = try deflateDecompress(
                    data: Data(compressedData),
                    uncompressedSize: entry.uncompressedSize
                )
                try decompressed.write(to: fileURL)
            default:
                throw ZIPExtractorError.unsupportedCompressionMethod(entry.compressionMethod)
            }
        }
    }

    // MARK: - Lectura del directorio central

    private nonisolated static func parseCentralDirectory(zipData: Data) throws -> [CentralDirEntry] {
        guard zipData.count >= 22 else { throw ZIPExtractorError.invalidSignature }

        // Buscar EOCD (End of Central Directory) desde el final
        var eocdOffset = -1
        let searchStart = max(0, zipData.count - 22 - 65535)
        for i in stride(from: zipData.count - 22, through: searchStart, by: -1) {
            if zipData.readUInt32LE(at: i) == 0x06054b50 {
                eocdOffset = i
                break
            }
        }
        guard eocdOffset >= 0 else { throw ZIPExtractorError.invalidSignature }

        let cdStart = Int(zipData.readUInt32LE(at: eocdOffset + 16))
        let cdSize  = Int(zipData.readUInt32LE(at: eocdOffset + 12))
        guard cdStart >= 0, cdStart + cdSize <= zipData.count else {
            throw ZIPExtractorError.invalidSignature
        }

        var entries: [CentralDirEntry] = []
        var offset = cdStart
        let cdEnd = cdStart + cdSize

        while offset + 46 <= cdEnd {
            guard zipData.readUInt32LE(at: offset) == 0x02014b50 else { break }

            let method          = zipData.readUInt16LE(at: offset + 10)
            let compressedSize  = Int(zipData.readUInt32LE(at: offset + 20))
            let uncompressedSize = Int(zipData.readUInt32LE(at: offset + 24))
            let fnLen           = Int(zipData.readUInt16LE(at: offset + 28))
            let extraLen        = Int(zipData.readUInt16LE(at: offset + 30))
            let commentLen      = Int(zipData.readUInt16LE(at: offset + 32))
            let localOffset     = Int(zipData.readUInt32LE(at: offset + 42))

            let fnData = zipData[offset + 46 ..< min(offset + 46 + fnLen, zipData.count)]
            let fileName = String(data: fnData, encoding: .utf8)
                        ?? String(data: fnData, encoding: .isoLatin1)
                        ?? ""

            entries.append(CentralDirEntry(
                fileName: fileName,
                compressionMethod: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))

            offset += 46 + fnLen + extraLen + commentLen
        }

        return entries
    }

    // MARK: - Descompresión DEFLATE (raw) mediante Compression framework

    private nonisolated static func deflateDecompress(data: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        // COMPRESSION_DEFLATE = 0x500 (raw DEFLATE, sin cabecera zlib ni gzip)
        let algorithm = compression_algorithm(0x500)
        let bufferSize = max(uncompressedSize, data.count * 4)
        var result = Data(count: bufferSize)

        let decompressedSize: Int = result.withUnsafeMutableBytes { destPtr in
            data.withUnsafeBytes { srcPtr in
                compression_decode_buffer(
                    destPtr.bindMemory(to: UInt8.self).baseAddress!,
                    bufferSize,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    algorithm
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
    nonisolated func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    nonisolated func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 3 < count else { return 0 }
        return UInt32(self[offset])
             | (UInt32(self[offset + 1]) << 8)
             | (UInt32(self[offset + 2]) << 16)
             | (UInt32(self[offset + 3]) << 24)
    }
}
