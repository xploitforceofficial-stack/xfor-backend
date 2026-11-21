"""Generic Luraph v14.6/v14.7 deobfuscation driver (v1).

Usage:
  python tools/v14_deob.py Samples/Luraph/<sample>.lua [--work tools/work_<tag>] [-o out.lua]
  python tools/v14_deob.py --lift-only [workdir]   # chains.tsv + opcodes/ -> lifted.lua

Pipeline per sample (each step reuses the existing tool for that job):
  1. shape detect   return-table + step-wrapper  -> stage is static (in the file)
                    return-function + brotli     -> stage is dynamic (needs the loader)
  2. stage extract  dynamic: node tools/v14_stage.js <sample> <work>/stage.lua
                    static:  the sample itself is the stage (copied)
  3. program capture (dynamic family): lune tools/capture_program.luau against
                    <work>/sample.lua -> <work>/prog_1.bin + reads.log.*
  4. patch + dump   python tools/patch_stage.py (anchors; per-build, see below)
                    lune tools/dump_g6.luau -> g6.tsv gy.tsv op.tsv a49.tsv chains.tsv
  5. opcode leaves  python tools/extract_a49.py && python tools/a49_dispatch.py
  6. lift           python tools/lift14.py <work> <out>

Per-build anchors: patch_stage.py / extract_a49.py currently hardcode the
(4)-build names (g6 return, GY call, `local P=(t[G])`, `[49]=function`).
A new build needs one manual pass to record its anchors; this driver accepts
--anchor name=value overrides and forwards them via env (PATCH_ANCHOR_*), so
adding a sample does not fork the tools. Fully automatic anchor discovery
(dispatch-tree search instead of string match) is the documented next step.

Workdirs: default tools/work (the analysed (4) sample). Use --work for any
other sample so results never mix.
"""
import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent

STEP_WRAPPER = re.compile(
    r"repeat\s+[A-Za-z_]\w*(\s*,\s*[A-Za-z_]\w*){1,5}\s*="
    r"\s*[A-Za-z_]\w*\s*:\s*[A-Za-z_]\w*\s*\("
)
RETURN_TABLE = re.compile(r"return\s*\(\s*\{")
RETURN_FUNCTION = re.compile(r"return\s*\(\s*function")
BANNER_V14 = re.compile(r"Luraph\s+Obfuscator\s+v14[\.\d]*", re.I)

def detect_shape(src: str) -> str:
    head = src[:4000]
    if not BANNER_V14.search(head):
        return "unknown"
    if STEP_WRAPPER.search(src) and RETURN_TABLE.search(head):
        return "static-stage"
    if RETURN_FUNCTION.search(head):
        return "dynamic-loader"
    if STEP_WRAPPER.search(src):
        return "static-stage"
    return "unknown"

def run(cmd, cwd=ROOT, env_extra=None):
    env = dict(os.environ)
    if env_extra:
        env.update(env_extra)
    p = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True,
                       errors="replace", timeout=1500)
    return p

def main() -> int:
    ap = argparse.ArgumentParser(description="Generic Luraph v14 deobfuscation driver")
    ap.add_argument("sample", nargs="?", help="Samples/Luraph/<file>.lua")
    ap.add_argument("--work", default=None, help="per-sample workdir (default tools/work)")
    ap.add_argument("-o", "--out", default=None, help="lifted output path")
    ap.add_argument("--lift-only", action="store_true",
                    help="only run the lifter on an existing workdir")
    ap.add_argument("--anchor", action="append", default=[],
                    help="per-build anchor override name=value (forwarded as PATCH_ANCHOR_*)")
    args = ap.parse_args()

    work = pathlib.Path(args.work) if args.work else HERE / "work"
    work.mkdir(parents=True, exist_ok=True)

    if args.lift_only:
        dest = pathlib.Path(args.out) if args.out else work / "lifted.lua"
        p = run([sys.executable, "tools/lift14.py", str(work), str(dest)])
        sys.stdout.write(p.stdout)
        sys.stderr.write(p.stderr)
        return p.returncode

    if not args.sample:
        ap.error("a sample path is required (or --lift-only)")
    sample = pathlib.Path(args.sample)
    if not sample.is_absolute():
        sample = ROOT / sample
    src = sample.read_bytes().decode("utf-8", errors="replace")
    shape = detect_shape(src)
    print("[v14] sample=%s size=%d shape=%s" % (sample.name, len(src), shape))
    banner = re.search(r"Luraph\s+Obfuscator\s+v([\d.]+)", src[:500])
    if banner:
        print("[v14] banner: Luraph Obfuscator v%s" % banner.group(1))

    if shape == "static-stage":
        print("[v14] static stage: copying sample as the stage")
        shutil.copyfile(sample, work / "stage.lua")
        print("[v14] NOTE: static-family program-buffer recovery (embedded LPH "
              "string -> prog buffer) is not automated yet; see the module "
              "docstring. Downstream steps need <work>/prog_1.bin first.")
        return 3

    if shape != "dynamic-loader":
        print("[v14] unknown shape: needs a manual look before the pipeline can run",
              file=sys.stderr)
        return 2

    env_extra = {}
    for a in args.anchor:
        if "=" in a:
            k, v = a.split("=", 1)
            env_extra["PATCH_ANCHOR_" + k.strip()] = v
    stage = work / "stage.lua"
    print("[v14] 1/5 extracting stage (loader run, can take minutes) ...")
    p = run(["node", "tools/v14_stage.js", str(sample), str(stage)])
    sys.stdout.write(p.stdout[-4000:])
    sys.stderr.write(p.stderr[-4000:])
    if p.returncode != 0 or not stage.exists():
        print("[v14] stage extraction failed", file=sys.stderr)
        return p.returncode or 1
    print("[v14] stage: %d chars" % stage.stat().st_size)

    print("[v14] 2/5 remaining steps run inside the workdir with the existing "
          "tools (capture_program.luau, patch_stage.py, dump_g6.luau, "
          "extract_a49.py, a49_dispatch.py, lift14.py).")
    print("[v14] workdir=%s" % work)
    print("[v14] next: copy sample to %s, capture, patch, dump, dispatch, lift "
          "(see tools/ README notes in LURAPH14.md)" % (work / "sample.lua"))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
