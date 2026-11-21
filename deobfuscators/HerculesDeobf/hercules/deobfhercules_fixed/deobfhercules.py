from __future__ import annotations
import argparse
import os
import sys
import time
import threading
from pathlib import Path

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

from deobfhercules import deobfuscate, deobfuscate_file, DeobfResult

_IS_WINDOWS = sys.platform == "win32"

class _TimeoutError(Exception):
    pass

def _arm_timeout(seconds: float):

    if seconds <= 0:
        return lambda: None

    if _IS_WINDOWS:
        def _fire():
            sys.stderr.write(
                f"\n[TIMEOUT] deobfuscation exceeded {seconds:.1f}s, "
                f"force-exiting (Windows cannot interrupt the main thread)\n"
            )
            sys.stderr.flush()
            os._exit(2)

        timer = threading.Timer(seconds, _fire)
        timer.daemon = True
        timer.start()
        return timer.cancel
    else:
        import signal

        def _handler(signum, frame):
            raise _TimeoutError(f"deobfuscation exceeded {seconds:.1f}s timeout")

        signal.signal(signal.SIGALRM, _handler)
        signal.setitimer(signal.ITIMER_REAL, seconds)

        def _disarm():
            signal.setitimer(signal.ITIMER_REAL, 0)

        return _disarm

def _format_result(input_path: str, output_path: str, result: DeobfResult, elapsed: float) -> str:
    if not result.success:
        return f"[FAIL] {input_path}: {result.error}"
    extra = ""
    if result.error:
        extra = f"  (warning: {result.error.splitlines()[0]})"
    stats = result.stats or {}
    return (
        f"[OK]   {input_path} -> {output_path}  "
        f"({result.mode}, {stats.get('top_instrs','?')} top instrs, "
        f"{stats.get('raw_bytes','?')} bytes, {elapsed:.2f}s){extra}"
    )

def process_one(input_path: str, output_path: str, mode: str, timeout: float = 30.0) -> DeobfResult:

    prefer = "disassembly" if mode == "disassembly" else "decompiled"
    t0 = time.time()

    if mode in ("source", "bytecode"):
        disarm = _arm_timeout(timeout)
        try:
            with open(input_path, "r", encoding="utf-8", errors="replace") as f:
                src = f.read()

            import deobfhercules as _pkg
            if mode == "bytecode":

                orig = _pkg._extract_embedded_source
                _pkg._extract_embedded_source = lambda chunk: None
                try:
                    result = _pkg.deobfuscate(src, prefer="decompiled")
                finally:
                    _pkg._extract_embedded_source = orig
            else:
                result = _pkg.deobfuscate(src, prefer="decompiled")
                if result.success and result.mode != "source":
                    result = DeobfResult(
                        success=False, mode="skipped", output="",
                        error="No embedded source found in this payload (try --mode bytecode or decompiled).",
                    )
            if result.success and result.output:
                with open(output_path, "w", encoding="utf-8") as f:
                    f.write(result.output)
        except _TimeoutError as e:
            result = DeobfResult(
                success=False, mode="skipped", output="",
                error=f"TIMEOUT: {e}",
            )
        except Exception as e:
            result = DeobfResult(
                success=False, mode="skipped", output="",
                error=f"unexpected error: {e}",
            )
        finally:
            disarm()
    else:
        disarm = _arm_timeout(timeout)
        try:
            result = deobfuscate_file(input_path, output_path, prefer=prefer)
        except _TimeoutError as e:
            result = DeobfResult(
                success=False, mode="skipped", output="",
                error=f"TIMEOUT: {e}",
            )
        except Exception as e:
            result = DeobfResult(
                success=False, mode="skipped", output="",
                error=f"unexpected error: {e}",
            )
        finally:
            disarm()

    elapsed = time.time() - t0
    print(_format_result(input_path, output_path, result, elapsed))

    if mode == "both" and result.success:

        asm_path = output_path + ".asm"
        t1 = time.time()
        disarm2 = _arm_timeout(timeout)
        try:
            r2 = deobfuscate_file(input_path, asm_path, prefer="disassembly")
        except _TimeoutError as e:
            r2 = DeobfResult(success=False, mode="skipped", output="",
                             error=f"TIMEOUT: {e}")
        except Exception as e:
            r2 = DeobfResult(success=False, mode="skipped", output="",
                             error=f"unexpected error: {e}")
        finally:
            disarm2()
        print(_format_result(input_path, asm_path, r2, time.time() - t1))
    return result

def process_batch(input_dir: str, output_dir: str, mode: str, timeout: float = 30.0) -> int:

    in_root = Path(input_dir)
    out_root = Path(output_dir)
    out_root.mkdir(parents=True, exist_ok=True)

    files = sorted(in_root.rglob("*.lua"))
    if not files:
        print(f"[INFO] No .lua files found under {input_dir}")
        return 0

    total = len(files)
    success = 0
    skipped = 0
    failed = 0
    t_total = time.time()

    for idx, fpath in enumerate(files, 1):
        rel = fpath.relative_to(in_root)

        out_subdir = out_root / rel.parent
        out_subdir.mkdir(parents=True, exist_ok=True)

        stem = fpath.stem
        if stem.endswith(".deobf"):
            out_name = stem + ".lua"
        else:
            out_name = stem + ".deobf.lua"
        out_path = out_subdir / out_name

        print(f"[{idx}/{total}] ", end="", flush=True)
        result = process_one(str(fpath), str(out_path), mode, timeout=timeout)
        if result.success:
            success += 1
        elif result.mode == "skipped":
            skipped += 1
        else:
            failed += 1

    elapsed = time.time() - t_total
    print()
    print(f"Batch complete: {success}/{total} succeeded, {skipped} skipped, {failed} failed, {elapsed:.2f}s total")
    return 0 if failed == 0 else 1

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="deobfhercules",
        description="Automatic static deobfuscator for Hercules-obfuscated Lua.",
    )
    parser.add_argument(
        "input",
        nargs="?",
        help="Input .lua file (single-file mode) or input directory (--batch mode).",
    )
    parser.add_argument(
        "output",
        nargs="?",
        help="Output .lua file (single-file mode) or output directory (--batch mode).",
    )
    parser.add_argument(
        "--mode",
        choices=["decompiled", "disassembly", "both", "source", "bytecode"],
        default="decompiled",
        help=(
            "Output mode (default: decompiled).\n"
            "  decompiled  - best readable output: extract embedded source if "
            "available (BytecodeEncoder path), else decompile bytecode.\n"
            "  source      - force embedded-source extraction only (fails if "
            "no source is embedded).\n"
            "  bytecode    - force structural bytecode decompilation (skip "
            "source extraction).\n"
            "  disassembly - luac -l style bytecode listing.\n"
            "  both        - write both decompiled (.lua) and disassembly (.asm)."
        ),
    )
    parser.add_argument(
        "--batch",
        action="store_true",
        help="Process every .lua file under <input> recursively into <output>.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=30.0,
        help="Per-file wall-clock timeout in seconds (default: 30). "
             "Use 0 to disable. On Unix, a timeout is a catchable exception "
             "(batch continues). On Windows, a timeout force-exits the process.",
    )
    args = parser.parse_args(argv)

    if not args.input:
        parser.print_help()
        return 1

    if args.batch:
        if not args.output:
            print("[ERROR] --batch requires an output directory")
            return 1
        return process_batch(args.input, args.output, args.mode, timeout=args.timeout)

    if not args.output:
        print("[ERROR] single-file mode requires both input and output paths")
        return 1

    result = process_one(args.input, args.output, args.mode, timeout=args.timeout)
    return 0 if result.success else 2

if __name__ == "__main__":
    sys.exit(main())
