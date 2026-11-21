"""Enum category tables stringify as Enum.<Name> (the client prints the full path)."""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATH = os.path.join(ROOT, "envlogger", "src", "env", "stdlib.luau")

with io.open(PATH, "r", encoding="utf-8", newline="") as fh:
    text = fh.read()

old = (
    '\t\tlocal expression = sym.expression\n'
    '\t\tif type(expression) == "string"\n'
    '\t\t\tand (sym.typeName == "Rect" or sym.typeName == "NumberRange") then'
)

new = (
    '\t\tlocal expression = sym.expression\n'
    '\t\tif sym.typeName == "Enum" and type(expression) == "string"\n'
    '\t\t\tand string.match(expression, "^Enum%.[%w_]+$") ~= nil then\n'
    '\t\t\treturn expression\n'
    '\t\tend\n'
    '\t\tif type(expression) == "string"\n'
    '\t\t\tand (sym.typeName == "Rect" or sym.typeName == "NumberRange") then'
)

old2 = (
    '\t\t\t\taddrCache[v] = cached\n'
    '\t\t\tend\n'
    '\t\t\treturn cached\n'
    '\t\tend\n'
    '\t\treturn s\n'
    '\tend'
)

new2 = (
    '\t\t\t\taddrCache[v] = cached\n'
    '\t\t\tend\n'
    '\t\t\treturn cached\n'
    '\t\tend\n'
    '\t\t-- enum category tables otherwise fall back to the bare type name\n'
    '\t\tif s == "Enum" then\n'
    '\t\t\tlocal path = datatypeString(v)\n'
    '\t\t\tif path ~= nil then\n'
    '\t\t\t\treturn path\n'
    '\t\t\tend\n'
    '\t\tend\n'
    '\t\treturn s\n'
    '\tend'
)

applied = 0
for o, n in ((old, new), (old2, new2)):
    hit = None
    for cand in (o, o.replace("\n", "\r\n")):
        if text.count(cand) == 1:
            hit = cand
            break
    if hit is None:
        sys.exit("anchor not found: " + o.splitlines()[0][:50])
    text = text.replace(hit, n.replace("\n", "\r\n") if "\r\n" in hit else n)
    applied += 1

with io.open(PATH, "w", encoding="utf-8", newline="") as fh:
    fh.write(text)
print("applied %d edits to stdlib.luau" % applied)
