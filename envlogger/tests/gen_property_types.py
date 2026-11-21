"""Emit className -> {propName: valueType} (inheritance-resolved) as a Luau
table snippet, spliced into classdata.luau for goal/property type validation."""
import json

DUMP = r"C:/Users/Sandr/OneDrive/Desktop/OmniDBF/Samples/api/Full-API-Dump.json"
OUT = r"C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_prop_types_snippet.luau"

with open(DUMP, encoding="utf-8") as f:
    data = json.load(f)

super_map = {c["Name"]: c.get("Superclass") for c in data["Classes"]}
props = {}
for c in data["Classes"]:
    entries = {}
    for m in c.get("Members", []):
        if m.get("MemberType") == "Property":
            vt = m.get("ValueType")
            if vt and vt.get("Name"):
                entries[m["Name"]] = vt["Name"]
    props[c["Name"]] = entries

def resolve(cls, seen=None):
    seen = seen or set()
    if cls in seen or cls not in props:
        return {}
    seen.add(cls)
    out = dict(props[cls])
    sup = super_map.get(cls)
    if sup:
        out.update(resolve(sup, seen))
    return out

resolved = {c: resolve(c) for c in props}
total = sum(len(v) for v in resolved.values())
print("classes:", len(resolved), "props:", total)

def luau_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

lines = ["\tlocal PROPERTY_TYPES: { [string]: { [string]: string } } = {"]
for cls in sorted(resolved):
    entries = resolved[cls]
    if not entries:
        continue
    parts = [f"[{luau_str(k)}] = {luau_str(v)}" for k, v in sorted(entries.items())]
    chunks = []
    cur = []
    for p in parts:
        cur.append(p)
        if sum(len(x) for x in cur) > 220:
            chunks.append(cur)
            cur = []
    if cur:
        chunks.append(cur)
    lines.append(f"\t\t[{luau_str(cls)}] = {{")
    for ch in chunks:
        lines.append("\t\t\t" + ", ".join(ch) + ",")
    lines.append("\t\t},")
lines.append("\t}")
with open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print("snippet written, lines:", len(lines))
