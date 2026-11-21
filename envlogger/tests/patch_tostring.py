"""tostring fidelity: datatypes -> type name (or arg list), EnumItem -> Enum.Cat.Item."""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ENV = os.path.join(ROOT, "envlogger", "src", "env")

STDLIB_OLD = (
    '\tlocal addrCounter = 0\n'
    '\tlocal addrCache: { [any]: string } = setmetatable({}, { __mode = "k" })\n'
    '\tlocal function toRobloxString(v: any): string\n'
    '\t\tlocal s = tostring(v)\n'
    '\t\tlocal prefix, hex = string.match(s, "^(%w+: 0x)(%x+)$")\n'
    '\t\tif prefix and #hex > 8 then\n'
)

STDLIB_NEW = (
    '\tlocal addrCounter = 0\n'
    '\tlocal addrCache: { [any]: string } = setmetatable({}, { __mode = "k" })\n'
    '\n'
    '\t-- Datatypes with no custom string form print as their type name in the\n'
    '\t-- client. A raw "table: 0x..." address is an instant tell, so resolve the\n'
    '\t-- symbolic name instead; argument-style datatypes print their arguments.\n'
    '\tlocal function datatypeString(v: any): string?\n'
    '\t\tlocal target = v\n'
    '\t\tif Spy.is(v) then\n'
    '\t\t\tlocal inner = Spy.unwrap(v)\n'
    '\t\t\tif inner ~= nil then\n'
    '\t\t\t\ttarget = inner\n'
    '\t\t\tend\n'
    '\t\tend\n'
    '\t\tlocal sym = Symbol.get(target)\n'
    '\t\tif sym == nil or type(sym.typeName) ~= "string" or sym.typeName == "" then\n'
    '\t\t\treturn nil\n'
    '\t\tend\n'
    '\t\tlocal expression = sym.expression\n'
    '\t\tif type(expression) == "string"\n'
    '\t\t\tand (sym.typeName == "Rect" or sym.typeName == "NumberRange") then\n'
    '\t\t\tlocal args = string.match(expression, "^%w+%.new%((.*)%)$")\n'
    '\t\t\tif args ~= nil then\n'
    '\t\t\t\treturn args\n'
    '\t\t\tend\n'
    '\t\tend\n'
    '\t\treturn sym.typeName\n'
    '\tend\n'
    '\n'
    '\tlocal function toRobloxString(v: any): string\n'
    '\t\tlocal s = tostring(v)\n'
    '\t\tlocal prefix, hex = string.match(s, "^(%w+: 0x)(%x+)$")\n'
    '\t\tif prefix and #hex > 8 then\n'
    '\t\t\tlocal named = datatypeString(v)\n'
    '\t\t\tif named ~= nil then\n'
    '\t\t\t\treturn named\n'
    '\t\t\tend\n'
)

ENUM_OLD = (
    '\t__tostring = function(self)\n'
    '\t\treturn self.Name\n'
    '\tend,'
)

ENUM_NEW = (
    '\t__tostring = function(self)\n'
    '\t\t-- the client prints the fully qualified path, e.g. "Enum.Material.Plastic"\n'
    '\t\tlocal sym = Symbol.get(self)\n'
    '\t\tif sym ~= nil and type(sym.expression) == "string" and sym.expression ~= "" then\n'
    '\t\t\treturn sym.expression\n'
    '\t\tend\n'
    '\t\tlocal category = self.EnumType\n'
    '\t\tif category ~= nil then\n'
    '\t\t\tlocal categorySym = Symbol.get(category)\n'
    '\t\t\tlocal categoryName = categorySym and categorySym.expression or nil\n'
    '\t\t\tif type(categoryName) == "string" and categoryName ~= "" then\n'
    '\t\t\t\treturn categoryName .. "." .. tostring(self.Name)\n'
    '\t\t\tend\n'
    '\t\tend\n'
    '\t\treturn tostring(self.Name)\n'
    '\tend,'
)

CATEGORY_OLD = (
    '\t\t\tSymbol.tag(categoryTable, {\n'
    '\t\t\t\tkind = "datatype",\n'
    '\t\t\t\texpression = "Enum." .. key,\n'
    '\t\t\t\ttypeName = "Enum",\n'
    '\t\t\t})'
)

CATEGORY_NEW = (
    '\t\t\tSymbol.tag(categoryTable, {\n'
    '\t\t\t\tkind = "datatype",\n'
    '\t\t\t\texpression = "Enum." .. key,\n'
    '\t\t\t\ttypeName = "Enum",\n'
    '\t\t\t})\n'
    '\t\t\tlocal categoryMeta = getmetatable(categoryTable)\n'
    '\t\t\tif type(categoryMeta) == "table" then\n'
    '\t\t\t\tcategoryMeta.__tostring = function(): string\n'
    '\t\t\t\t\treturn "Enum." .. key\n'
    '\t\t\t\tend\n'
    '\t\t\tend'
)

EDITS = [
    ("stdlib.luau", STDLIB_OLD, STDLIB_NEW),
    ("enumitem.luau", 'local Fidelity = require("./fidelity")',
     'local Fidelity = require("./fidelity")\nlocal Symbol = require("../core/symbol")'),
    ("enumitem.luau", ENUM_OLD, ENUM_NEW),
    ("roblox.luau", CATEGORY_OLD, CATEGORY_NEW),
]

failures = []
for filename, old, new in EDITS:
    path = os.path.join(ENV, filename)
    with io.open(path, "r", encoding="utf-8", newline="") as fh:
        text = fh.read()
    hit = None
    for cand in (old, old.replace("\n", "\r\n")):
        if text.count(cand) == 1:
            hit = cand
            break
    if hit is None:
        failures.append((filename, old.splitlines()[0][:60]))
        continue
    text = text.replace(hit, new.replace("\n", "\r\n") if "\r\n" in hit else new)
    with io.open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    print("patched", filename)

if failures:
    print("FAILED:")
    for filename, head in failures:
        print("  ", filename, "->", head)
    sys.exit(1)
print("all tostring edits applied")
