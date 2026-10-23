# Brotli decoder dependency

Only `c/common`, `c/dec`, `c/include/brotli` and `LICENSE` are vendored.

- Upstream: Google Brotli, tag `v1.2.0`
- Pinned commit: `028fb5a23661f123017c060daa546b55cf4bde29`
- License: MIT, full upstream text in `LICENSE`
- No upstream build or installation script is executed.
- Download manifest: project `logs/brotli-v1.2.0-manifest.json`

The decoder is used for HTTP `Content-Encoding: br`. Output size is bounded by
the caller's explicit limit, and malformed/truncated streams do not become a
successful JSON/HTML/image response.
