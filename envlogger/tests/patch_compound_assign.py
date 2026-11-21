"""Stop the safe-indexing pass from rewriting index targets of `+=` style writes.

Before: `t[i] += 1` became `__FUHD_SAFE_INDEX__(t, i) += 1`, which cannot compile,
so any Luau script using indexed compound assignment failed inside the sandbox.
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATH = os.path.join(ROOT, "envlogger", "src", "core", "srcedit.luau")

with io.open(PATH, "r", encoding="utf-8", newline="") as fh:
    text = fh.read()

old = """\t\t\tlocal nxt: any = toks[closeIdx + 1]
\t\t\tif nxt and nxt.raw == "=" then continue end
"""

new = """\t\t\tlocal nxt: any = toks[closeIdx + 1]
\t\t\tif nxt and nxt.raw == "=" then continue end

\t\t\t-- compound assignment writes (`t[i] += 1`, `t[i] ..= "x"`) are lvalues
\t\t\t-- too: wrapping them yields `__FUHD_SAFE_INDEX__(...) += 1`, which does
\t\t\t-- not compile. Skip the target when an assignment follows.
\t\t\tdo
\t\t\t\tlocal raw = nxt and nxt.raw or nil
\t\t\t\tlocal isAssign = raw == "+=" or raw == "-=" or raw == "*=" or raw == "/="
\t\t\t\t\tor raw == "%=" or raw == "^=" or raw == "..="
\t\t\t\tif not isAssign and raw ~= nil then
\t\t\t\t\tlocal splitsInto = raw == "+" or raw == "-" or raw == "*" or raw == "/"
\t\t\t\t\t\tor raw == "%" or raw == "^" or raw == ".."
\t\t\t\t\tif splitsInto then
\t\t\t\t\t\tlocal after = toks[closeIdx + 2]
\t\t\t\t\t\t-- tokenizers that split `+=` into `+` `=` land here
\t\t\t\t\t\tif after and after.raw == "=" then
\t\t\t\t\t\t\tisAssign = true
\t\t\t\t\t\tend
\t\t\t\t\tend
\t\t\t\tend
\t\t\t\tif isAssign then continue end
\t\t\tend
"""

variants = [(old, new)]
applied = False
for o, n in variants:
    for oo in (o, o.replace("\n", "\r\n")):
        if text.count(oo) == 1:
            text = text.replace(oo, n.replace("\n", "\r\n") if "\r\n" in oo else n)
            applied = True
            break
    if applied:
        break

if not applied:
    sys.exit("anchor not found")

with io.open(PATH, "w", encoding="utf-8", newline="") as fh:
    fh.write(text)
print("patched srcedit.luau")
