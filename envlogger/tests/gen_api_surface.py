"""Generate envlogger enum + class tables from the official Roblox API dump.

Outputs:
  envlogger/src/env/enumvalues.luau  -- all 600+ enums with real item values
  envlogger/src/env/classdata.luau   -- superclass chain, creatable set, service set

Both files are plain data, so the sandbox never has to guess (guessing is what
coarse anti-tamper scripts fingerprint).
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DUMP = os.path.join(ROOT, "Samples", "api", "API-Dump.json")
OUT = os.path.join(ROOT, "envlogger", "src", "env")

def luau_str(s):
    s = str(s)
    out = s.replace("\\", "\\\\").replace('"', '\\"')
    return '"%s"' % out

def luau_key(name):
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name) and name not in RESERVED:
        return name
    return "[" + luau_str(name) + "]"

def luau_value(name):
    return luau_str(name)

RESERVED = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
    "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true",
    "until", "while", "continue", "export", "type",
}

d = json.load(open(DUMP, encoding="utf-8"))
classes = d["Classes"]
enums = d["Enums"]
version = d.get("Version", "unknown")

lines = []
lines.append("--!nonstrict")
lines.append("-- Generated from the Roblox API dump (%s)." % version)
lines.append("-- Do not hand-edit: regenerate with tests/gen_api_surface.py.")
lines.append("")
lines.append("local EnumValues = {}")
lines.append("")
lines.append("local VALUES: { [string]: { [string]: number } } = {")
total_items = 0
for e in sorted(enums, key=lambda x: x["Name"]):
    name = e["Name"]
    items = e.get("Items") or []
    if not items:
        continue
    lines.append("\t%s = {" % luau_key(name))
    row = []
    for it in items:
        row.append("%s = %d" % (luau_key(it["Name"]), it["Value"]))
        total_items += 1
    for i in range(0, len(row), 4):
        lines.append("\t\t" + ", ".join(row[i:i + 4]) + ",")
    lines.append("\t},")
lines.append("}")
lines.append("")
lines.append("local ceilings: { [string]: number } = {}")
lines.append("for category, items in pairs(VALUES) do")
lines.append("\tlocal highest = 0")
lines.append("\tfor _, value in pairs(items) do")
lines.append("\t\tif value > highest then")
lines.append("\t\t\thighest = value")
lines.append("\t\tend")
lines.append("\tend")
lines.append("\tceilings[category] = highest")
lines.append("end")
lines.append("")
lines.append("function EnumValues.get(category: string, item: string): number?")
lines.append("\tlocal items = VALUES[category]")
lines.append("\tif items == nil then")
lines.append("\t\treturn nil")
lines.append("\tend")
lines.append("\treturn items[item]")
lines.append("end")
lines.append("")
lines.append("function EnumValues.floor(category: string): number")
lines.append("\tlocal ceiling = ceilings[category]")
lines.append("\tif ceiling == nil then")
lines.append("\t\treturn 0")
lines.append("\tend")
lines.append("\treturn ceiling + 1")
lines.append("end")
lines.append("")
lines.append("function EnumValues.items(category: string): { [string]: number }?")
lines.append("\treturn VALUES[category]")
lines.append("end")
lines.append("")
lines.append("function EnumValues.hasCategory(category: string): boolean")
lines.append("\treturn VALUES[category] ~= nil")
lines.append("end")
lines.append("")
lines.append("return EnumValues")
lines.append("")
open(os.path.join(OUT, "enumvalues.luau"), "w", encoding="utf-8", newline="\n").write("\n".join(lines))

super_of = {}
known = set()
service = set()
creatable = set()
for c in classes:
    name = c["Name"]
    tags = c.get("Tags") or []
    known.add(name)
    parent = c.get("Superclass")
    if parent:
        super_of[name] = parent
    if "Service" in tags:
        service.add(name)
    if "NotCreatable" not in tags:
        creatable.add(name)

cl = []
cl.append("--!nonstrict")
cl.append("-- Generated from the Roblox API dump (%s)." % version)
cl.append("-- Do not hand-edit: regenerate with tests/gen_api_surface.py.")
cl.append("")
cl.append("local ClassData = {}")
cl.append("")
cl.append("ClassData.VERSION = " + luau_str(version))
cl.append("")
cl.append("-- every class the client knows about, mapped to its superclass")
cl.append("local SUPERCLASS: { [string]: string } = {")
row = []
for name in sorted(super_of):
    row.append("%s = %s" % (luau_key(name), luau_value(super_of[name])))
for i in range(0, len(row), 3):
    cl.append("\t" + ", ".join(row[i:i + 3]) + ",")
cl.append("}")
cl.append("")
for label, data in (("CREATABLE", sorted(creatable)), ("SERVICE", sorted(service))):
    cl.append("-- %d names" % len(data))
    cl.append("local %s: { [string]: boolean } = {" % label)
    row = []
    for name in data:
        row.append("%s = true" % luau_key(name))
    for i in range(0, len(row), 3):
        cl.append("\t" + ", ".join(row[i:i + 3]) + ",")
    cl.append("}")
    cl.append("")
cl.append("local ALL: { [string]: boolean } = {}")
cl.append("for name in pairs(SUPERCLASS) do")
cl.append("\tALL[name] = true")
cl.append("end")
cl.append("for name in pairs(CREATABLE) do")
cl.append("\tALL[name] = true")
cl.append("end")
cl.append("for name in pairs(SERVICE) do")
cl.append("\tALL[name] = true")
cl.append("end")
cl.append("ALL.Instance = true")
cl.append("")
cl.append("local chainCache: { [string]: { string } } = {}")
cl.append("")
cl.append("function ClassData.ancestors(name: string): { string }")
cl.append("\tlocal cached = chainCache[name]")
cl.append("\tif cached then")
cl.append("\t\treturn cached")
cl.append("\tend")
cl.append("\tlocal chain: { string } = { name }")
cl.append("\tlocal seen: { [string]: boolean } = { [name] = true }")
cl.append("\tlocal current = SUPERCLASS[name]")
cl.append("\twhile current ~= nil and not seen[current] do")
cl.append("\t\tchain[#chain + 1] = current")
cl.append("\t\tseen[current] = true")
cl.append("\t\tcurrent = SUPERCLASS[current]")
cl.append("\tend")
cl.append("\tif not seen.Instance then")
cl.append("\t\tchain[#chain + 1] = \"Instance\"")
cl.append("\tend")
cl.append("\tchainCache[name] = chain")
cl.append("\treturn chain")
cl.append("end")
cl.append("")
cl.append("function ClassData.isA(selfClass: string, asked: string): boolean")
cl.append("\tif asked == selfClass or asked == \"Instance\" then")
cl.append("\t\treturn true")
cl.append("\tend")
cl.append("\tif asked == nil or asked == \"\" then")
cl.append("\t\treturn false")
cl.append("\tend")
cl.append("\tlocal chain = ClassData.ancestors(selfClass)")
cl.append("\tfor _, base in ipairs(chain) do")
cl.append("\t\tif base == asked then")
cl.append("\t\t\treturn true")
cl.append("\t\tend")
cl.append("\tend")
cl.append("\treturn false")
cl.append("end")
cl.append("")
cl.append("function ClassData.isCreatable(name: string): boolean")
cl.append("\treturn CREATABLE[name] == true")
cl.append("end")
cl.append("")
cl.append("function ClassData.isService(name: string): boolean")
cl.append("\treturn SERVICE[name] == true")
cl.append("end")
cl.append("")
cl.append("function ClassData.isKnown(name: string): boolean")
cl.append("\treturn ALL[name] == true")
cl.append("end")
cl.append("")
cl.append("function ClassData.creatableNames(): { string }")
cl.append("\tlocal names: { string } = {}")
cl.append("\tfor name in pairs(CREATABLE) do")
cl.append("\t\tnames[#names + 1] = name")
cl.append("\tend")
cl.append("\ttable.sort(names)")
cl.append("\treturn names")
cl.append("end")
cl.append("")
cl.append("return ClassData")
cl.append("")
open(os.path.join(OUT, "classdata.luau"), "w", encoding="utf-8", newline="\n").write("\n".join(cl))

print("wrote enumvalues.luau: %d enums, %d items" % (sum(1 for e in enums if e.get("Items")), total_items))
print("wrote classdata.luau: %d known, %d creatable, %d services" % (len(known), len(creatable), len(service)))
