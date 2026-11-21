"""Extract default property values for classes from the Roblox API dump
(Full-API-Dump.json carries the 'Default' field) and emit a lazy Luau table
that the sandbox serves as instance property defaults.

The emitted module defers construction: roblox.luau installs the enum resolver
and the sandbox's own datatype constructors before the first lookup, so values
are the sandbox's tagged datatypes (typeof-correct), not Lune natives.
"""
import json

DUMP = r"C:/Users/Sandr/OneDrive/Desktop/OmniDBF/Samples/api/Full-API-Dump.json"
OUT = r"C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/src/env/propdefaults.luau"

def _nums(default, n):
    """Parse the dump's comma-separated numeric default ('0, 0, 0')."""
    try:
        parts = [float(p) for p in str(default).split(",")]
        if len(parts) < n:
            parts += [0.0] * (n - len(parts))
        return parts[:n]
    except (ValueError, AttributeError):
        return [0.0] * n

def _fmt(x):
    if x != x:
        return "0/0"
    if x == float("inf"):
        return "math.huge"
    if x == float("-inf"):
        return "-math.huge"
    return repr(int(x)) if float(x).is_integer() else repr(x)

def _vec3(default):
    x, y, z = _nums(default, 3)
    return f'{{ c = "Vector3", {x!r}, {y!r}, {z!r} }}' if False else \
        f'{{ c = "Vector3", a = {{ {_fmt(x)}, {_fmt(y)}, {_fmt(z)} }} }}'

def _vec2(default):
    x, y = _nums(default, 2)
    return f'{{ c = "Vector2", a = {{ {_fmt(x)}, {_fmt(y)} }} }}'

def _color3(default):
    r, g, b = _nums(default, 3)
    return f'{{ c = "Color3", a = {{ {_fmt(r)}, {_fmt(g)}, {_fmt(b)} }} }}'

def _number_range(default):
    lo, hi = _nums(default, 2)
    return f'{{ c = "NumberRange", a = {{ {_fmt(lo)}, {_fmt(hi)} }} }}'

def _rect(default):
    a, b, c, d = _nums(default, 4)
    return f'{{ c = "Rect", a = {{ {_fmt(a)}, {_fmt(b)}, {_fmt(c)}, {_fmt(d)} }} }}'

def _udim(default):
    s, o = _nums(default, 2)
    return f'{{ c = "UDim", a = {{ {_fmt(s)}, {_fmt(o)} }} }}'

def _udim2(default):
    xs, xo, ys, yo = _nums(default, 4)
    return f'{{ c = "UDim2", a = {{ {_fmt(xs)}, {_fmt(xo)}, {_fmt(ys)}, {_fmt(yo)} }} }}'

def _cframe(default):

    parts = _nums(default, 12)
    if parts == [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]:
        return '{ c = "CFrame", a = {} }'
    return f'{{ c = "CFrame", a = {{ {", ".join(_fmt(p) for p in parts)} }} }}'

SPECIAL_TYPES = {
    "Vector3": _vec3,
    "Vector3int16": lambda v: '{ c = "Vector3int16", a = {} }',
    "Vector2": _vec2,
    "Color3": _color3,
    "NumberRange": _number_range,
    "Rect": _rect,
    "UDim": _udim,
    "UDim2": _udim2,
    "CFrame": _cframe,
    "ColorSequence": lambda v: '{ c = "ColorSequence", a = {} }',
    "NumberSequence": lambda v: '{ c = "NumberSequence", a = {} }',
    "Faces": lambda v: '{ c = "Faces", a = {} }',
    "Axes": lambda v: '{ c = "Axes", a = {} }',
    "Ray": lambda v: '{ c = "Ray", a = {} }',
    "TweenInfo": lambda v: '{ c = "TweenInfo", a = {} }',
    "PhysicalProperties": lambda v: '{ c = "PhysicalProperties", a = { 0.7, 0.3, 0.5 } }',
    "Font": lambda v: '{ c = "Font", a = {} }',
    "Region3": lambda v: '{ c = "Region3", a = {} }',
    "BrickColor": lambda v: '{ c = "BrickColor", a = { "Medium stone grey" } }',
    "SharedTable": lambda v: None,
    "SecurityCapabilities": lambda v: None,
    "Content": lambda v: '""',
    "ContentId": lambda v: '""',
    "BinaryString": lambda v: '""',
}

ENUM_PREFIX = "Enum."

def render_lua_value(member):
    dt = member.get("ValueType", {})
    tname = dt.get("Name", "")
    default = member.get("Default", None)

    if dt.get("Category") == "Enum":
        if default is not None and str(default) != "":
            return f'{{ c = "EnumItem", a = {{ "{tname}", "{default}" }} }}'
        return f'{{ c = "EnumItem", a = {{ "{tname}" }} }}'

    if tname in SPECIAL_TYPES:
        fn = SPECIAL_TYPES[tname]
        if default is None:
            if tname == "PhysicalProperties":
                return '{ c = "PhysicalProperties", a = { 0.7, 0.3, 0.5 } }'
            return fn("") if fn("") is not None else None
        return fn(default)

    if tname == "bool":
        return "true" if str(default).lower() == "true" else "false"
    if tname in ("float", "double", "int", "int64", "long"):
        if default is None:
            return None
        return str(default)
    if tname == "string":
        return json.dumps(default if default is not None else "")
    return None

def main():
    with open(DUMP, encoding="utf-8") as f:
        dump = json.load(f)

    classes = {c["Name"]: c for c in dump["Classes"]}

    supermap = {c["Name"]: c.get("Superclass") for c in dump["Classes"]}

    def declared_props(cname):
        cls = classes.get(cname)
        if cls is None:
            return {}
        entries = {}
        for member in cls.get("Members", []):
            if member.get("MemberType") != "Property":
                continue
            raw_tags = member.get("Tags") or []
            tags = set(t for t in raw_tags if isinstance(t, str))
            if "NotScriptable" in tags:
                continue

            if str(member.get("Default", "")).startswith("__api_dump"):
                continue
            rendered = render_lua_value(member)
            if rendered is None:
                continue
            entries[member["Name"]] = rendered
        return entries

    def inherited_props(cname):
        chain = []
        seen = set()
        cur = supermap.get(cname)
        while cur and cur not in seen:
            chain.append(cur)
            seen.add(cur)
            cur = supermap.get(cur)
        merged = {}
        for base in reversed(chain):
            merged.update(declared_props(base))
        return merged

    out_lines = []
    out_lines.append("--!nonstrict")
    out_lines.append("-- Generated from the Roblox API dump: default property values per class.")
    out_lines.append("-- Values are DESCRIPTORS resolved lazily by roblox.luau through the")
    out_lines.append("-- sandbox's own datatype constructors, so typeof() matches the client.")
    out_lines.append("-- Do not hand-edit: regenerate with tests/gen_prop_defaults.py.")
    out_lines.append("")
    out_lines.append("local PropDefaults = {}")
    out_lines.append("")
    out_lines.append("local RESOLVE: ((string, { any }) -> any)? = nil")
    out_lines.append("")
    out_lines.append("function PropDefaults.installResolver(fn: (string, { any }) -> any)")
    out_lines.append("\tRESOLVE = fn")
    out_lines.append("end")
    out_lines.append("")
    out_lines.append("local DEFAULTS: { [string]: { [string]: any } } = {")

    total_props = 0
    for cname in sorted(classes):
        entries = inherited_props(cname)
        entries.update(declared_props(cname))

        if not entries:
            continue
        total_props += len(entries)
        out_lines.append(f"\t{cname} = {{")
        for pname in sorted(entries):
            out_lines.append(f'\t\t{pname} = {entries[pname]},')
        out_lines.append("\t},")

    out_lines.append("}")
    out_lines.append("")
    out_lines.append("-- returns a plain table className -> CONSTRUCTED values; roblox.luau calls")
    out_lines.append("-- this once per Roblox.build with its own datatypes + Enum installed")
    out_lines.append("function PropDefaults.materialize(): { [string]: { [string]: any } }")
    out_lines.append("\tlocal resolve = RESOLVE")
    out_lines.append("\tlocal out: { [string]: { [string]: any } } = {}")
    out_lines.append("\tfor className, props in pairs(DEFAULTS) do")
    out_lines.append("\t\tlocal built: { [string]: any } = {}")
    out_lines.append("\t\tfor propName, descriptor in pairs(props) do")
    out_lines.append("\t\t\tif type(descriptor) == \"table\" and type(descriptor.c) == \"string\" then")
    out_lines.append("\t\t\t\tlocal ok, value = pcall(resolve, descriptor.c, descriptor.a)")
    out_lines.append("\t\t\t\tbuilt[propName] = if ok then value else nil")
    out_lines.append("\t\t\telse")
    out_lines.append("\t\t\t\tbuilt[propName] = descriptor")
    out_lines.append("\t\t\tend")
    out_lines.append("\t\tend")
    out_lines.append("\t\tout[className] = built")
    out_lines.append("\tend")
    out_lines.append("\treturn out")
    out_lines.append("end")
    out_lines.append("")
    out_lines.append("function PropDefaults.count(): number")
    out_lines.append("\tlocal n = 0")
    out_lines.append("\tfor _ in pairs(DEFAULTS) do n += 1 end")
    out_lines.append("\treturn n")
    out_lines.append("end")
    out_lines.append("")
    out_lines.append("return PropDefaults")
    out_lines.append("")

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out_lines))
    print(f"wrote {OUT}: {len(classes)} classes scanned, {total_props} default props emitted")

if __name__ == "__main__":
    main()
