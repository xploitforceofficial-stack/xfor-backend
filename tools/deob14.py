"""Run the v14 lift pipeline end to end for one workdir and report status.

The per-build steps (opcode-leaf extraction, chain join, lift, simplify,
validate) already exist as separate tools, but they need per-family flags and
were only ever driven by hand. This encodes the two verified configurations so a
build is reproducible with one command:

    python tools/deob14.py tools/work            # canonical (v14.7 (4)) family
    python tools/deob14.py tools/work_s2         # multi-loop (v14.7 (2)) family

Family selection is by marker, not by path, so a fresh workdir works:

  canonical  op.tsv is `pc<TAB>opcode`; pc register G, registers d,
             operand arrays t,i,w,D,f,O,z  (leaf extraction is already
             recorded in work/a49_full.lua)
  s2         op.tsv is `pc<TAB>opcode<TAB>loop`; pc register F, registers r,
             operand arrays m,N,h,y,f,d,n, and the dispatch-table state in
             zstate.tsv is needed to fold the opaque branches

Outputs (all inside the workdir):
  opcodes/        one leaf per opcode
  chains_post.tsv operand table (post-patch)
  lifted.lua      full dispatch form - always written
  simple.lua      user-level symbolic form - may be sparse
  deob14.json     machine-readable status

Exit code is 0 whenever *something* usable was produced, so a partially
recovered build is a release, not a crash. The status in deob14.json is the
honest signal.
"""
import json
import pathlib
import re
import subprocess
import sys

TOOLS = pathlib.Path(__file__).resolve().parent
REPO = TOOLS.parent

S2_RUNTIME = ("D|E|Y|t|V|c|v|F|b|P|Z|g|s|J|I|l|U|p|H|e|q|N|f|d|h|y|r|O|C|m|w"
              "|a|k|G")

FAMILIES = {
    "canonical": {
        "marker_cols": 2,
        "src": "a49_full.lua",
        "fetch": "local P=(t[G]);",
        "opvar": "P",
        "runtimenames": None,
        "junkconsts": "D=172",
        "junkdecls": "local D=172",
        "zstate": None,
        "assignednames": None,
        "join": "join_chains.py",
    },
    "s2": {
        "marker_cols": 3,
        "src": "a49_F.lua",
        "fetch": "local C=(m[F]);",
        "opvar": "C",
        "runtimenames": S2_RUNTIME,
        "junkconsts": "D=172",
        "junkdecls": "local D=172",
        "zstate": "zstate.tsv",
        "assignednames": "_",
        "join": "join_s2.py",
    },
}

def detect_family(work: pathlib.Path) -> str:
    op = work / "op.tsv"
    if op.exists():
        for line in op.read_text(encoding="utf-8").splitlines():
            if line.strip():
                return "s2" if len(line.split("\t")) >= 3 else "canonical"
    return "canonical"

def run(cmd, cwd=REPO):
    p = subprocess.run([str(c) for c in cmd], cwd=str(cwd), capture_output=True,
                       text=True, encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip()

def tail(text: str, n: int = 2) -> str:
    lines = [l for l in text.splitlines() if l.strip()]
    return " | ".join(lines[-n:]) if lines else ""

def main() -> int:
    work = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else TOOLS / "work"
    work = work if work.is_absolute() else (pathlib.Path.cwd() / work)
    if not work.is_dir():
        print("no such workdir: %s" % work, file=sys.stderr)
        return 2

    fam = detect_family(work)
    cfg = FAMILIES[fam]
    steps = []

    def record(name, rc, out, err, critical=True):
        steps.append({"step": name, "rc": rc, "out": tail(out), "err": tail(err, 1),
                      "critical": critical})
        if rc != 0:
            print("[deob14] %s FAILED rc=%d %s" % (name, rc, tail(err, 1)), file=sys.stderr)
        return rc == 0

    print("[deob14] workdir=%s family=%s" % (work, fam))

    src = work / cfg["src"]
    if not src.exists():
        print("[deob14] missing dispatch source %s - run the extract step first" % src,
              file=sys.stderr)
        steps.append({"step": "extract", "rc": 2, "out": "", "err": str(src),
                      "critical": True})
        write_status(work, fam, steps, None, None)
        return 2

    cmd = [sys.executable, TOOLS / "a49_dispatch.py",
           "--work", work, "--src", src, "--fetch", cfg["fetch"],
           "--opvar", cfg["opvar"], "--out", work / "opcodes",
           "--opts", "op.tsv", "--chains", "chains_post.tsv",
           "--junkconsts", cfg["junkconsts"], "--junkdecls", cfg["junkdecls"]]
    if cfg["runtimenames"]:
        cmd += ["--runtimenames", cfg["runtimenames"]]
    if cfg["zstate"] and (work / cfg["zstate"]).exists():
        cmd += ["--zstate", work / cfg["zstate"]]
    else:
        print("[deob14] note: no zstate.tsv; opaque dispatch branches stay unfolded")
    if cfg["assignednames"]:
        cmd += ["--assignednames", cfg["assignednames"]]
    record("a49_dispatch", *run(cmd)[:3])

    join = TOOLS / cfg["join"]
    if join.exists():
        record("join", *run([sys.executable, join, work])[:3])
    else:
        print("[deob14] note: %s not found; using existing chains_post.tsv" % join.name)

    record("lift14", *run([sys.executable, TOOLS / "lift14.py", work])[:3])

    rc, so, se = run([sys.executable, TOOLS / "simplify14.py", work])
    steps.append({"step": "simplify14", "rc": rc, "out": tail(so), "err": tail(se, 1),
                  "critical": False})

    rc, vo, ve = run([sys.executable, TOOLS / "validate14.py", work])
    steps.append({"step": "validate14", "rc": rc, "out": tail(vo, 3), "err": tail(ve, 1),
                  "critical": False})

    simple = parse_simple(work / "simple.lua", so)
    status = write_status(work, fam, steps, simple, parse_validate(vo))
    print("[deob14] %s" % status["summary"])
    return 0

def parse_simple(path: pathlib.Path, stdout: str = ""):
    """Chain tallies come from the artifact; the statement count is only
    reported on stdout by simplify14, so read it from there."""
    if not path.exists():
        return None
    txt = path.read_text(encoding="utf-8", errors="replace")
    counts = {"complete": 0, "approx": 0, "partial": 0}
    for m in re.finditer(r"simulation:\s+(complete|approx|partial)", txt):
        counts[m.group(1)] += 1
    stmts = None
    m2 = re.search(r"(\d+)\s+statements", stdout)
    if m2:
        stmts = int(m2.group(1))
    return {"chains": counts, "statements": stmts}

def parse_validate(out: str):
    m = re.search(r"jump transitions:\s*(\d+)\s+match:\s*(\d+)\s+rate:\s*([\d.]+)", out)
    f = re.search(r"fallthrough:\s*(\d+)\s+advance:\s*(\d+)\s+rate:\s*([\d.]+)", out)
    return {
        "jumps": {"tested": int(m.group(1)), "match": int(m.group(2)),
                  "rate": float(m.group(3))} if m else None,
        "fallthrough": {"tested": int(f.group(1)), "advance": int(f.group(2)),
                        "rate": float(f.group(3))} if f else None,
    }

def write_status(work, fam, steps, simple, validate):
    crit_fail = [s["step"] for s in steps if s["critical"] and s["rc"] != 0]
    have_lift = (work / "lifted.lua").exists()
    n_stmt = (simple or {}).get("statements") or 0
    if crit_fail or not have_lift:
        grade = "failed"
    elif n_stmt == 0:
        grade = "dispatch-only"
    else:
        grade = "user-level"
    status = {
        "family": fam,
        "workdir": str(work),
        "grade": grade,
        "lifted": have_lift,
        "simple": simple,
        "validate": validate,
        "steps": steps,
        "summary": "grade=%s family=%s%s" % (
            grade, fam,
            "" if simple is None else
            " chains complete=%d approx=%d partial=%d statements=%d" % (
                simple["chains"]["complete"], simple["chains"]["approx"],
                simple["chains"]["partial"], simple["statements"] or 0)),
    }
    (work / "deob14.json").write_text(json.dumps(status, indent=1), encoding="utf-8")
    return status

if __name__ == "__main__":
    raise SystemExit(main())
