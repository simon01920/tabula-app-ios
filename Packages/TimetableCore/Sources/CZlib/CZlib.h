#ifndef TABULA_CZLIB_H
#define TABULA_CZLIB_H

// Shim over the system zlib for TimetableCore's share codec.
//
// Swift cannot call zlib's function-like macros (deflateInit2, inflateInit2), and `z_stream.next_in` is
// `Bytef *` or `const Bytef *` depending on ZLIB_CONST, so the few operations the codec needs are wrapped
// in static inline functions with one fixed signature on every platform.

#include <zlib.h>

/// Starts a raw DEFLATE stream (window bits -15: no zlib/gzip header or trailer), memLevel 8,
/// default strategy, at `level` (0...9).
static inline int tabula_deflate_init_raw(z_streamp stream, int level) {
    return deflateInit2(stream, level, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY);
}

/// Starts a raw INFLATE stream (window bits -15).
static inline int tabula_inflate_init_raw(z_streamp stream) {
    return inflateInit2(stream, -15);
}

/// Points the stream's input at `bytes[0..<count]`.
static inline void tabula_zstream_set_input(z_streamp stream, const unsigned char *bytes, unsigned int count) {
    stream->next_in = (Bytef *)bytes;
    stream->avail_in = (uInt)count;
}

/// Points the stream's output at `bytes[0..<count]`.
static inline void tabula_zstream_set_output(z_streamp stream, unsigned char *bytes, unsigned int count) {
    stream->next_out = (Bytef *)bytes;
    stream->avail_out = (uInt)count;
}

/// Unconsumed input bytes.
static inline unsigned int tabula_zstream_avail_in(z_streamp stream) {
    return (unsigned int)stream->avail_in;
}

/// Unused output space.
static inline unsigned int tabula_zstream_avail_out(z_streamp stream) {
    return (unsigned int)stream->avail_out;
}

#endif
