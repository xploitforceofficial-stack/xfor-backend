"""Real zstd decompression for envlogger's fake EncodingService.

The bundled pure-Luau decoder (src/env/zstd.luau) handles the common frames but
still fails on some FSE/Huffman combinations. When it does, services.luau calls
this script so the guest sees correct plaintext instead of an
"invalid zstd input" error - which, for a Luraph loader, means the payload stays
sealed and nothing is recovered.

Files rather than stdin/stdout: the payload is binary and the host bridge is
simplest with paths.

Usage: python zstd_host.py <in.bin> <out.bin>
Exit: 0 on success, non-zero with a message on stderr.
"""
import sys

def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: zstd_host.py <in.bin> <out.bin>\n")
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    try:
        import zstandard
    except ImportError as exc:
        sys.stderr.write("zstandard unavailable: %s\n" % exc)
        return 3
    with open(src, "rb") as fh:
        data = fh.read()
    dctx = zstandard.ZstdDecompressor()
    try:
        out = dctx.decompress(data)
    except Exception:

        try:
            out = dctx.decompressobj().decompress(data)
        except Exception as exc:
            sys.stderr.write("decompress failed: %s\n" % exc)
            return 4
    with open(dst, "wb") as fh:
        fh.write(out)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
