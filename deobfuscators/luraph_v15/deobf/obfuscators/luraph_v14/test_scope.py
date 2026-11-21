"""
Tests for scope-aware operand injection (scope.py).

Run:  python obfuscators/luraph_v14/test_scope.py [decrypted_stage.lua]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, HERE)

import luauast
import scope

FAILS = []

def ok(name, cond, detail=""):
    if cond:
        print("ok   " + name)
    else:
        print("FAIL " + name + ((" -> " + str(detail)) if detail else ""))
        FAILS.append(name)

def reparse(text):
    try:
        luauast.parse(text)
        return True, None
    except Exception as e:
        return False, e

NL = "\n"

SYNTH = NL.join([
    "local l,A,C,Q,H,j",
    "while true do",
    "  if Q==8.0 then Q=(71); continue;",
    "  elseif Q==102.0 then Q=(13); continue;",
    "  end",
    "end",
    "",
])

TWO = NL.join([
    "local a,s1",
    "while true do if s1==1 then continue end end",
    "local b,s2",
    "while true do if s2==2 then continue end end",
    "",
])

def test_synthetic():
    new, info = scope.inject(SYNTH)
    ok("synth: one loop", len(info) == 1, len(info))
    if info:
        ok("synth: state is Q", info[0]["state"] == "Q", info[0]["state"])
        ok("synth: tags 8 and 102", sorted(info[0]["tags"], key=float) == [8, 102],
           info[0]["tags"])
        ok("synth: operands exclude the state slot",
           "Q" not in info[0]["operands"], info[0]["operands"])
        ok("synth: operands are the sibling locals",
           info[0]["operands"] == ["l", "A", "C", "H", "j"], info[0]["operands"])
    good, err = reparse(new)
    ok("synth: patched source reparses", good, err)
    at = new.find("__LPH_REG_TRACE__")
    after_do = new.find("while true do")
    ok("synth: trace call is inside the loop body", after_do >= 0 and at > after_do,
       new[:200])

def test_scope_isolation():
    new, info = scope.inject(TWO)
    ok("two loops: both found", len(info) == 2, len(info))
    if len(info) == 2:

        ok("two loops: second loop sees the block's locals",
           info[1]["operands"] == ["a", "s1", "b"], info[1]["operands"])
        ok("two loops: second loop uses its own state slot",
           info[1]["state"] == "s2" and "s2" not in info[1]["operands"],
           (info[1]["state"], info[1]["operands"]))
    good, err = reparse(new)
    ok("two loops: patched source reparses", good, err)

def test_no_false_positives():
    plain = NL.join([
        "local t = {}",
        "for i = 1, 10 do t[i] = i end",
        "while #t > 0 do table.remove(t) end",
        "return t",
        "",
    ])
    new, info = scope.inject(plain)
    ok("plain luau: no loops claimed", info == [], info)
    ok("plain luau: source untouched", new == plain)

def test_balanced_locals():
    """Five-operand cap, so the hook's a..e are all filled."""
    src = NL.join([
        "local a,b,c,d,e,f,g,S",
        "while true do if S==1 then continue end end",
        "",
    ])
    _new, info = scope.inject(src)
    ok("cap: at most five operands", info and len(info[0]["operands"]) == 5,
       info[0]["operands"] if info else None)
    ok("cap: operands pad to five", info and info[0]["operands"][:5] == ["a", "b", "c", "d", "e"],
       info[0]["operands"] if info else None)

def test_real_stage(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        src = f.read()
    new, info = scope.inject(src)
    ok("real: loops found", len(info) >= 10, len(info))
    ok("real: several state slots", len({i["state"] for i in info}) >= 3,
       sorted({i["state"] for i in info}))

    hot = max(info, key=lambda i: len(i["tags"]))
    ok("real: the hottest chain is instrumented", len(hot["tags"]) >= 3,
       hot["tags"])
    ok("real: the hottest chain has operands", len(hot["operands"]) >= 2,
       hot["operands"])

    numeric = all(isinstance(t, (int, float)) for i in info for t in i["tags"])
    ok("real: tags are numeric", numeric, [i["tags"][:3] for i in info[:3]])
    good, err = reparse(new)
    ok("real: patched stage reparses", good, err)

    growth = len(new) - len(src)
    ok("real: growth is bounded", growth < len(src) // 8, growth)
    print("\n  instrumented loops:")
    for i in info[:10]:
        print("    state %-4s tags %-18s ops %s"
              % (i["state"], str(i["tags"][:4]), i["operands"]))

def main():
    test_synthetic()
    test_scope_isolation()
    test_no_false_positives()
    test_balanced_locals()
    if len(sys.argv) > 1 and os.path.exists(sys.argv[1]):
        test_real_stage(sys.argv[1])
    else:
        print("skip real-stage case (pass a decrypted stage path)")
    if FAILS:
        print("\n%d FAILURES" % len(FAILS))
        return 1
    print("\nall good")
    return 0

if __name__ == "__main__":
    sys.exit(main())
