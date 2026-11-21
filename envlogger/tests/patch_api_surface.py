"""Wire the generated API surface into the sandbox (idempotent, verifies each edit)."""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ENV = os.path.join(ROOT, "envlogger", "src", "env")

edits = []

edits.append(("roblox.luau", [

    ('local EnumValues = require("./enumvalues")',
     'local ClassData = require("./classdata")\nlocal EnumValues = require("./enumvalues")'),

    ('\t\tlocal ancestors = CLASS_ANCESTORS[selfClass]',
     '\t\tif ClassData.isA(selfClass, asked) then\n'
     '\t\t\treturn true\n'
     '\t\tend\n'
     '\t\tlocal ancestors = CLASS_ANCESTORS[selfClass]'),

    ('\t\t\tif classDefaults[name] == nil and not Services.isKnownClassName(name) then',
     '\t\t\tif classDefaults[name] == nil and not ClassData.isCreatable(name) then'),

    ('\t\t\tlocal key = tostring(category)\n\t\t\tlocal existing = enumCache[key]',
     '\t\t\tlocal key = tostring(category)\n'
     '\t\t\tif not EnumValues.hasCategory(key) then\n'
     '\t\t\t\t-- the client has no such Enum; inventing one is a giveaway\n'
     '\t\t\t\treturn nil\n'
     '\t\t\tend\n'
     '\t\t\tlocal existing = enumCache[key]'),

    ('\t\t\t\t\tlocal made = itemCache[itemKey]\n\t\t\t\t\tif made then\n\t\t\t\t\t\treturn made\n\t\t\t\t\tend\n\t\t\t\t\treturn makeItem(itemKey)',
     '\t\t\t\t\tlocal made = itemCache[itemKey]\n'
     '\t\t\t\t\tif made then\n'
     '\t\t\t\t\t\treturn made\n'
     '\t\t\t\t\tend\n'
     '\t\t\t\t\tif EnumValues.get(key, itemKey) == nil then\n'
     '\t\t\t\t\t\t-- unknown member: the client yields nil here too\n'
     '\t\t\t\t\t\treturn nil\n'
     '\t\t\t\t\tend\n'
     '\t\t\t\t\treturn makeItem(itemKey)'),

    ('\t\t\t\tif made ~= nil then\n\t\t\t\t\treturn made\n\t\t\t\tend\n\t\t\t\treturn makeItem(itemName)',
     '\t\t\t\tif made ~= nil then\n'
     '\t\t\t\t\treturn made\n'
     '\t\t\t\tend\n'
     '\t\t\t\tif EnumValues.get(key, itemName) == nil then\n'
     '\t\t\t\t\treturn nil\n'
     '\t\t\t\tend\n'
     '\t\t\t\treturn makeItem(itemName)'),

    ('\t\t\t\t\t\t\tif #itemList < 2 then\n'
     '\t\t\t\t\t\t\t\tmakeItem("Default")\n'
     '\t\t\t\t\t\t\t\tif #itemList < 2 then\n'
     '\t\t\t\t\t\t\t\t\tmakeItem("None")\n'
     '\t\t\t\t\t\t\t\tend\n'
     '\t\t\t\t\t\t\tend\n',
     ''),
]))

edits.append(("services.luau", [
    ('local Datatypes = require("./datatypes")',
     'local ClassData = require("./classdata")\nlocal Datatypes = require("./datatypes")'),
    ('function Services.isService(name: any): boolean\n\treturn type(name) == "string" and byName[name] == true\nend',
     'function Services.isService(name: any): boolean\n'
     '\tif type(name) ~= "string" then\n'
     '\t\treturn false\n'
     '\tend\n'
     '\treturn byName[name] == true or ClassData.isService(name)\n'
     'end'),
    ('function Services.isKnownClassName(name: any): boolean\n\treturn type(name) == "string" and (byName[name] == true or INSTANCE_CLASSES[name] == true)\nend',
     'function Services.isKnownClassName(name: any): boolean\n'
     '\tif type(name) ~= "string" then\n'
     '\t\treturn false\n'
     '\tend\n'
     '\treturn byName[name] == true or INSTANCE_CLASSES[name] == true or ClassData.isKnown(name)\n'
     'end'),
]))

failures = []
for filename, pairs in edits:
    path = os.path.join(ENV, filename)
    with io.open(path, "r", encoding="utf-8", newline="") as fh:
        text = fh.read()
    for old, new in pairs:
        candidates = [old, old.replace("\n", "\r\n")]
        hit = None
        for cand in candidates:
            if text.count(cand) == 1:
                hit = cand
                break
        if hit is None:
            counts = [(text.count(c), repr(c[:60])) for c in candidates]
            failures.append((filename, old[:70], counts))
            continue
        text = text.replace(hit, new.replace("\n", "\r\n") if "\r\n" in hit else new)
    with io.open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    print("patched", filename)

if failures:
    print("\nFAILED EDITS:")
    for filename, old, counts in failures:
        print("  ", filename, "->", old, counts)
    sys.exit(1)
print("all edits applied")
