"""
Tests for the v14 ISA extractor.

Run:  python obfuscators/luraph_v14/test_isa.py
Exit code 0 = pass. The synthetic interpreter cases always run; the real-stage
case only runs when a decrypted stage is passed on the command line, because
producing one means a full sandbox run.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))

from obfuscators.luraph_v14 import isa

FAILS = []

def ok(name, cond, detail=""):
    if cond:
        print("ok   " + name)
    else:
        print("FAIL " + name + ((" -> " + str(detail)) if detail else ""))
        FAILS.append(name)

SYNTH = """
local l,A,C,Q,H,j
while true do
  if Q==8.0 then Q=(71); continue;
  elseif Q==102.0 then Q=(13); continue;
  else if Q==13.0 then Q=8; end
  end
end
"""

STEP = "local F,A,C,Q=(103); repeat A,F,Q,C=Y:z6(c,F,Q); if A==-2 then return C; end; until false"

def test_synthetic():
    t = isa.build_isa(SYNTH)
    ok("synth: state slot is Q", t["state"] == "Q", t["state"])
    ok("synth: three arms", t["interpreter_arms"] == 3, t["interpreter_arms"])
    ok("synth: tags are 8/13/102",
       sorted(t["tags"].keys()) == ["==102", "==13", "==8"],
       sorted(t["tags"].keys()))
    ok("synth: 8 -> 71", t["tags"]["==8"]["targets"] == ["71"], t["tags"]["==8"]["targets"])
    ok("synth: 102 -> 13", t["tags"]["==102"]["targets"] == ["13"], t["tags"]["==102"]["targets"])
    ok("synth: 13 -> 8", t["tags"]["==13"]["targets"] == ["8"], t["tags"]["==13"]["targets"])

def test_step_wrapper_flag():
    t = isa.build_isa(STEP)
    ok("step wrapper: recognised", t["step_wrapper"] is True)
    t2 = isa.build_isa("local x = 1")
    ok("step wrapper: not claimed for plain luau", t2["step_wrapper"] is False)
    ok("plain luau: no tables", t2["interpreters"] == [])

def test_canon():
    ok("canon 8.0 -> 8", isa._canon("8.0") == "8")
    ok("canon 8 -> 8", isa._canon("8") == "8")
    ok("canon 102.0 -> 102", isa._canon("102.0") == "102")

def test_empty():
    t = isa.build_isa("")
    ok("empty source is safe", t["tags"] == {} and t["interpreters"] == [])
    ok("empty render is empty", isa.render_isa(t) == "")

def test_render():
    r = isa.render_isa(isa.build_isa(SYNTH))
    ok("render names the state slot", "state slot Q" in r, r)
    ok("render lists a tag row", "==8" in r, r)
    ok("render shows the transition", "next: 71" in r, r)

def test_real_stage(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        src = f.read()
    t = isa.build_isa(src)
    tables = t["interpreters"]
    ok("real: state slot found", bool(t["state"]))
    ok("real: step wrapper recognised", t["step_wrapper"] is True)
    ok("real: more than one dispatch chain", len(tables) >= 2, len(tables))
    ok("real: widest chain is substantial", t["interpreter_arms"] >= 20, t["interpreter_arms"])
    with_targets = sum(1 for tb in tables for v in tb["tags"].values() if v["targets"])
    ok("real: transitions recovered", with_targets > 20, with_targets)
    r = isa.render_isa(t)
    ok("real: render warns that tags are per-chain",
       "different instruction in each" in r or len(tables) == 1, r[:200])
    print("\n  chains in this stage:")
    for tb in tables[:8]:
        print("    state %-3s %3d arms  %3d tags" % (tb["state"], tb["arms"], len(tb["tags"])))

def main():
    test_canon()
    test_empty()
    test_step_wrapper_flag()
    test_synthetic()
    test_render()
    if len(sys.argv) > 1 and os.path.exists(sys.argv[1]):
        test_real_stage(sys.argv[1])
    else:
        print("skip real-stage case (pass a decrypted stage path to run it)")
    if FAILS:
        print("\n%d FAILURES" % len(FAILS))
        return 1
    print("\nall good")
    return 0

if __name__ == "__main__":
    sys.exit(main())
