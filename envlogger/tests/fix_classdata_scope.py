"""Hoist the ClassData require in services.luau above the functions that capture it."""
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
path = os.path.join(ROOT, "envlogger", "src", "env", "services.luau")
with io.open(path, "r", encoding="utf-8", newline="") as fh:
    text = fh.read()

for stale in ('local ClassData = require("./classdata")\r\n',
              'local ClassData = require("./classdata")\n'):
    if stale in text and text.count(stale) == 1:
        text = text.replace(stale, "")
        break
else:
    raise SystemExit("could not find the misplaced require")

anchor = "local Services = {}\n"
replacement = 'local Services = {}\n\nlocal ClassData = require("./classdata")\n'
if text.count(anchor) != 1:
    raise SystemExit("unexpected anchor count")
text = text.replace(anchor, replacement)

with io.open(path, "w", encoding="utf-8", newline="") as fh:
    fh.write(text)

head = text.splitlines()[:8]
print("services.luau head:")
for i, line in enumerate(head, 1):
    print("  %d: %s" % (i, line))
