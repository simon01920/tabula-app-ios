import CZlib

/// Raw DEFLATE (RFC 1951, no zlib/gzip framing) through the system zlib: window bits −15, level 9.
///
/// The compressed bytes are deterministic for a given zlib build and input; different zlib builds (Linux vs
/// Apple) may produce different — equally valid — streams. Decoding never depends on the exact bytes.
///
/// The `z_stream` lives in manually allocated memory: zlib keeps a back-pointer to it and rejects a stream
/// whose address changed, which Swift's `&value` argument passing does not rule out.
enum ShareDeflate {
    /// Compression level (0…9).
    static let level: Int32 = 9
    /// Output chunk size of the streaming inflater.
    static let inflateChunk = 16_384
    /// Largest input either direction accepts (zlib counts in 32 bits; the codec stays far below).
    static let maxInputBytes = 1 << 30

    /// Compresses `input` in one pass.
    static func compress(_ input: [UInt8]) throws(ShareError) -> [UInt8] {
        guard input.count <= maxInputBytes else { throw .compressionFailed }
        let stream = UnsafeMutablePointer<z_stream>.allocate(capacity: 1)
        stream.initialize(to: z_stream())
        defer { stream.deinitialize(count: 1); stream.deallocate() }
        guard tabula_deflate_init_raw(stream, level) == Z_OK else { throw .compressionFailed }
        defer { deflateEnd(stream) }

        let bound = Int(deflateBound(stream, uLong(input.count)))
        var output = [UInt8](repeating: 0, count: bound)
        let status: Int32 = input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                // zlib accepts a null input pointer together with a zero count.
                tabula_zstream_set_input(stream, inputBuffer.baseAddress, UInt32(inputBuffer.count))
                tabula_zstream_set_output(stream, outputBuffer.baseAddress, UInt32(outputBuffer.count))
                return deflate(stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { throw .compressionFailed }
        let produced = bound - Int(tabula_zstream_avail_out(stream))
        return Array(output.prefix(produced))
    }

    /// Inflates one complete raw DEFLATE stream, producing at most `maxOutput` bytes.
    ///
    /// - Throws: `.decompressedTooLarge` as soon as the output would exceed `maxOutput` (the rest of the input is
    ///   never inflated); `.decompressionFailed` for an empty, corrupt or truncated stream, a stream that needs a
    ///   preset dictionary, or bytes after the end of the stream.
    static func decompress(_ input: [UInt8], maxOutput: Int) throws(ShareError) -> [UInt8] {
        guard !input.isEmpty, input.count <= maxInputBytes else { throw .decompressionFailed }
        let stream = UnsafeMutablePointer<z_stream>.allocate(capacity: 1)
        stream.initialize(to: z_stream())
        defer { stream.deinitialize(count: 1); stream.deallocate() }
        guard tabula_inflate_init_raw(stream) == Z_OK else { throw .decompressionFailed }
        defer { inflateEnd(stream) }

        var output: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: inflateChunk)
        let result: Result<[UInt8], ShareError> = input.withUnsafeBufferPointer { inputBuffer in
            tabula_zstream_set_input(stream, inputBuffer.baseAddress, UInt32(inputBuffer.count))
            while true {
                let inputBefore = tabula_zstream_avail_in(stream)
                let status: Int32 = chunk.withUnsafeMutableBufferPointer { chunkBuffer in
                    tabula_zstream_set_output(stream, chunkBuffer.baseAddress, UInt32(chunkBuffer.count))
                    return inflate(stream, Z_NO_FLUSH)
                }
                let produced = inflateChunk - Int(tabula_zstream_avail_out(stream))
                if output.count + produced > maxOutput { return .failure(.decompressedTooLarge) }
                output.append(contentsOf: chunk.prefix(produced))
                switch status {
                case Z_STREAM_END:
                    // Strict: nothing may follow the final block.
                    return tabula_zstream_avail_in(stream) == 0 ? .success(output) : .failure(.decompressionFailed)
                case Z_OK:
                    // zlib makes progress whenever it returns Z_OK; guard against a livelock regardless.
                    if produced == 0 && tabula_zstream_avail_in(stream) == inputBefore {
                        return .failure(.decompressionFailed)
                    }
                default:
                    // Z_BUF_ERROR (input ended before the stream did — output space is never zero here),
                    // Z_DATA_ERROR, Z_NEED_DICT, Z_MEM_ERROR, Z_STREAM_ERROR.
                    return .failure(.decompressionFailed)
                }
            }
        }
        return try result.get()
    }
}
