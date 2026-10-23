#ifndef VENERA_HTTP_DECODING_H
#define VENERA_HTTP_DECODING_H
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>
#include <zlib.h>
#include <brotli/decode.h>

namespace venera {
inline bool InflateBody(const uint8_t* input, size_t length, int bits, size_t limit,
                        bool concatenate_gzip, std::vector<uint8_t>* output, std::string* error) {
  if (length > UINT32_MAX) { *error = "compressed input too large"; return false; }
  z_stream stream{};
  stream.zalloc = [](void*, uInt count, uInt size) -> void* { return std::calloc(count, size); };
  stream.zfree = [](void*, void* pointer) { std::free(pointer); };
  if (inflateInit2(&stream, bits) != Z_OK) { *error = "zlib initialization failed"; return false; }
  stream.next_in = const_cast<Bytef*>(input);
  stream.avail_in = static_cast<uInt>(length);
  output->clear();
  bool success = false;
  uint8_t chunk[16384];
  for (;;) {
    stream.next_out = chunk;
    stream.avail_out = sizeof(chunk);
    const uInt before = stream.avail_in;
    int code = inflate(&stream, Z_NO_FLUSH);
    size_t produced = sizeof(chunk) - stream.avail_out;
    if (output->size() > limit || produced > limit - output->size()) {
      *error = "decoded body exceeds configured limit"; break;
    }
    output->insert(output->end(), chunk, chunk + produced);
    if (code == Z_STREAM_END) {
      if (stream.avail_in == 0) { success = true; break; }
      if (concatenate_gzip && stream.avail_in >= 2 && stream.next_in[0] == 0x1f && stream.next_in[1] == 0x8b) {
        auto* remaining = stream.next_in; const uInt available = stream.avail_in;
        if (inflateReset2(&stream, bits) != Z_OK) { *error = "gzip member reset failed"; break; }
        stream.next_in = remaining; stream.avail_in = available; continue;
      }
      *error = "trailing bytes after compressed stream"; break;
    }
    if (code != Z_OK || (before == stream.avail_in && produced == 0)) {
      *error = "invalid or truncated compressed stream"; break;
    }
  }
  inflateEnd(&stream);
  if (!success) output->clear();
  return success;
}

inline bool DecodeHttpBody(const uint8_t* input, size_t length, const std::string& encoding,
                          size_t limit, std::vector<uint8_t>* output, std::string* error) {
  if (encoding == "gzip" || encoding == "x-gzip") {
    return InflateBody(input, length, MAX_WBITS + 16, limit, true, output, error);
  }
  if (encoding == "deflate") {
    // Some servers incorrectly use raw DEFLATE instead of RFC1950's wrapper.
    const bool zlib_header = length >= 2 && (input[0] & 0x0f) == Z_DEFLATED &&
      (input[0] >> 4) <= 7 && ((static_cast<unsigned>(input[0]) << 8) | input[1]) % 31 == 0;
    // A recognized wrapper with broken Adler32/trailing bytes is corrupt, not
    // an invitation to reinterpret it as another format.
    return InflateBody(input, length, zlib_header ? MAX_WBITS : -MAX_WBITS, limit, false, output, error);
  }
  if (encoding != "br") { *error = "unsupported content encoding"; return false; }
  BrotliDecoderState* state = BrotliDecoderCreateInstance(nullptr, nullptr, nullptr);
  if (!state) { *error = "Brotli initialization failed"; return false; }
  output->clear();
  const uint8_t* next_in = input; size_t available_in = length;
  uint8_t chunk[16384]; bool success = false;
  for (;;) {
    uint8_t* next_out = chunk; size_t available_out = sizeof(chunk);
    const size_t before = available_in;
    auto code = BrotliDecoderDecompressStream(state, &available_in, &next_in, &available_out, &next_out, nullptr);
    const size_t produced = sizeof(chunk) - available_out;
    if (output->size() > limit || produced > limit - output->size()) {
      *error = "decoded body exceeds configured limit"; break;
    }
    output->insert(output->end(), chunk, chunk + produced);
    if (code == BROTLI_DECODER_RESULT_SUCCESS) {
      success = available_in == 0;
      if (!success) *error = "trailing bytes after Brotli stream";
      break;
    }
    if (code == BROTLI_DECODER_RESULT_ERROR ||
        (code == BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT && available_in == 0) ||
        (before == available_in && produced == 0)) {
      *error = "invalid or truncated Brotli stream"; break;
    }
  }
  BrotliDecoderDestroyInstance(state);
  if (!success) output->clear();
  return success;
}
}
#endif
