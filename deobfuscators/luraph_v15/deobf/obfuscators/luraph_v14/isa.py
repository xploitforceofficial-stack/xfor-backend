"""
Luraph v14.x instruction set, recovered from the decrypted stage.

v14 never puts the user's program in the file as bytecode. The outer loader
decrypts a stage, and that stage is the *VM runtime*: a table of closures that
interprets the real program one dispatch step at a time. So the first thing
worth having is not a lifter output - it is a readable map of what the
interpreter's dispatch tags actually do, derived from the stage we just
decrypted.

Why derive it and not hardcode it: the tags are per-build. Across the sampled
builds the same numeric tag lands on different code, the local names differ per
closure, and the register/constant table indices differ. A table transcribed
from one sample and applied to another produces output that looks authoritative
and is wrong. Everything here is therefore read out of the stage in front of us.

Shapes handled (all verified against Samples/Luraph):

  step wrapper   local F,A,C,Q=(103); repeat A,F,Q,C=Y:z6(c,F,Q); if A==-2
                 then return C; end; until false
  interpreter   while true do if Q==8.0 then Q=(71); ... continue;
                 elseif Q==102.0 then Q=(13); ... continue; else ... end

The interpreter is a flat equality chain on one state slot, so each arm is one
instruction: the tag it tests, the body, and any tags it transitions to.
"""
import re

ARM_RE = re.compile(r"\b(?:if|elseif)\s+([A-Za-z_]\w*)\s*==\s*([0-9]+(?:\.0+)?)")

ASSIGN_RE = re.compile(r"\b([A-Za-z_]\w*)\s*=\s*\(\s*([0-9]+(?:\.0+)?)\s*\)"
                       r"|\b([A-Za-z_]\w*)\s*=\s*([0-9]+(?:\.0+)?)\b")

INDEX_RE = re.compile(r"([A-Za-z_]\w*)\[([0-9]+)\]")

ARM_HEAD_RE = re.compile(r"^\s*(?:else)?if\s+[A-Za-z_]\w*\s*==\s*"
                         r"[0-9]+(?:\.0+)?\s*then\b")

TABLE_OPS = ("table.move", "table.insert", "table.remove", "table.concat",
             "table.unpack", "unpack", "select", "setmetatable", "rawset", "rawget")
NUM_OPS = ("bit32.band", "bit32.bor", "bit32.bxor", "bit32.lshift", "bit32.rshift",
           "bit32.bnot", "math.floor", "math.ceil", "math.abs", "math.max", "math.min")
CONCAT = "+"
COMPARE = ("==", "~=", "<", ">", "<=", ">=")

OP_SYMBOL = {
    "CompareEq": "==", "CompareNe": "~=", "CompareLt": "<",
    "CompareLe": "<=", "CompareGt": ">", "CompareGe": ">=",
}

def _fmt_num(v):
    """A Luau numeric literal for `v`, so it can be inlined in a probe call."""
    if isinstance(v, float) and v == int(v):
        return "%d.0" % int(v)
    return repr(v)

def tag_key(op, val):
    """Readable table key for an arm: '==8', '<101', '>=30'."""
    return "%s%s" % (OP_SYMBOL.get(op, op or "?"), _canon(val))

def _canon(tag):
    """`8.0` and `8` are the same tag; Luraph writes them inconsistently."""
    try:
        f = float(tag)
    except (TypeError, ValueError):
        return tag
    return str(int(f)) if f == int(f) else repr(f)

def _split_arms(body):
    """[(tag, arm_source)] for one `if X==T ... elseif X==U ...` chain."""
    marks = []
    for m in ARM_RE.finditer(body):
        marks.append((m.start(), m.group(1), _canon(m.group(2))))
    if not marks:
        return []
    arms = []
    for i, (pos, _state, tag) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(body)
        arms.append((tag, body[pos:end]))
    return arms

def _targets(arm_src, state):
    """Tags this arm transitions to, i.e. the next instruction(s)."""
    out = []
    for m in ASSIGN_RE.finditer(arm_src):
        name = m.group(1) or m.group(3)
        val = m.group(2) or m.group(4)
        if name == state:
            t = _canon(val)
            if t not in out:
                out.append(t)
    return out

def find_interpreters(source):
    """
    [(chain key, [(tag, arm_source)])] - every dispatch chain in `source`.

    Grouped per FUNCTION, not per state name. Different closures reuse the same
    local names - a stage with seventeen chains has several that dispatch on a
    slot called `Q` - so grouping by name alone merges unrelated interpreters
    and invents tags that belong to another function. The chain key is
    (function id, state slot).
    """
    import luauast
    from obfuscators.ironbrew1 import instrument

    try:
        root = luauast.parse(source)
    except Exception:
        return []

    out = []

    by_fn = {}
    fid = [0]

    def walk(node):
        if isinstance(node, list):
            for x in node:
                walk(x)
            return
        if not isinstance(node, dict):
            return

        t = node.get("type")
        if t == "AstExprFunction":
            fid[0] += 1
            saved = fid[0]
            walk(node.get("body"))
            fid[0] = saved
            return
        if t == "AstStatBlock":
            for st in (node.get("body") or []):
                walk(st)
            return
        if t == "AstStatWhile":
            c = node.get("condition") or {}
            if c.get("type") == "AstExprConstantBool" and c.get("value"):
                body = (node.get("body") or {}).get("body") or []
                if body and body[0].get("type") == "AstStatIf":
                    chain = _arm_chain(body[0])
                    if chain:
                        state = chain[0][2]
                        if all(c[2] == state for c in chain):
                            slot = by_fn.setdefault(fid[0], {}).setdefault(state, [])
                            for op, val, _st, n in chain:
                                slot.append((n, (op, val), n.get("location", "")))
        for k, v in node.items():
            if k in ("local", "location"):
                continue
            if isinstance(v, (dict, list)):
                walk(v)

    walk(root)

    for fnid, states in by_fn.items():
        for state, entries in states.items():

            entries.sort(key=lambda e: _loc_key(e[2]))
            out.append(((fnid, state),
                        [(tag, node, loc) for node, tag, loc in entries],
                        state))
    return out

def _loc_key(location):
    """'12,3 - 12,9' -> a sortable tuple."""
    try:
        a, _, _b = location.partition(" - ")
        line, col = a.split(",")
        return (int(line), int(col))
    except Exception:
        return (0, 0)

def find_register_slot(bodies):
    """
    (name, index) of the register file in this build, or (None, None).

    On the sampled v14.7 stage the interpreter reads and writes `F[45]`, so the
    register file is `F[45]` - but both the name and the index are per build, so
    the pair is measured rather than assumed: the most common `name[N]` across
    the arms wins.
    """
    counts = {}
    for body in bodies:
        for m in INDEX_RE.finditer(body):
            key = (m.group(1), int(m.group(2)))
            counts[key] = counts.get(key, 0) + 1
    if not counts:
        return None, None
    (name, idx), _n = max(counts.items(), key=lambda kv: kv[1])
    return name, idx

def find_register_index(bodies):
    """The register file's index only. See find_register_slot for the pair."""
    return find_register_slot(bodies)[1]

def classify(body, reg_index):
    """
    What this arm does, read off its source.

    Deliberately coarse and evidence-based: a label plus the features that
    produced it, so a reader can check the reasoning instead of trusting it.
    Returns (label, [features]).
    """
    if not body:
        return ("empty", [])

    feats = []

    src = ARM_HEAD_RE.sub("", body, count=1)
    if not src.strip():
        src = body

    if "continue" in src:
        feats.append("continue")
    if re.search(r"\bbreak\b", src):
        feats.append("break")
    if re.search(r"\breturn\b", src):
        feats.append("return")

    if reg_index is not None:
        pat = r"\[[^\]]*\b%d\b[^\]]*\]" % reg_index
        if re.search(r"=[^=]", src) and re.search(pat, src):

            if re.search(r"[^=<>!+\-*/%%]" + pat + r"=[^=]", src):
                feats.append("store-reg")
        if re.search(pat, src):
            feats.append("use-reg")

    if any(op in src for op in NUM_OPS):
        feats.append("arith")
    if re.search(r"[%s]\s*=\s*[^=]*[%%^]", src):
        feats.append("arith")

    if any(op in src for op in TABLE_OPS):
        feats.append("table-op")

    calls = re.findall(r"([A-Za-z_]\w*)\[([^\]]+)\]\s*\(", src)
    if calls:
        feats.append("call:%d" % len(calls))
    if re.search(r"\w+\s*\(", src) and not calls:
        feats.append("call-named")

    if any(op in src for op in COMPARE):
        feats.append("compare")

    if "for " in src or "while " in src:
        feats.append("loop")

    if not feats:
        return ("nop?", [])

    for label, key in (("table-op", "table-op"),
                       ("arith", "arith"),
                       ("compare+branch", "compare"),
                       ("call", "call"),
                       ("store", "store-reg"),
                       ("load", "use-reg"),
                       ("loop", "loop")):
        if key in feats:
            return (label, feats)
    return (feats[0], feats)

COMPARE_OPS = ("CompareEq", "CompareNe", "CompareLt", "CompareLe", "CompareGt", "CompareGe")

def _arm_chain(node):
    """
    [(cmp, value, node)] for an if/elseif chain on ONE slot, else [].

    Not just `==`. The v14 interpreters are control-flow flattened and branch on
    ranges as well as equality - `elseif g<=2.0`, `elseif g<101.0 and g>30.0`,
    `elseif g<30.0` - and matching equality alone found 22 chains out of 194,
    missing the ones that actually execute the program.
    """
    out = []
    cur = node
    while isinstance(cur, dict) and cur.get("type") == "AstStatIf":
        cond = cur.get("condition") or {}
        got = _compare_operand(cond)
        if got is None:
            break
        out.append(got + (cur,))
        cur = cur.get("elsebody")
        while isinstance(cur, dict) and cur.get("type") == "AstStatBlock":
            body = cur.get("body") or []
            if len(body) != 1:
                cur = None
                break
            cur = body[0]
        if not (isinstance(cur, dict) and cur.get("type") == "AstStatIf"):
            cur = None
    return out

def _compare_operand(cond):
    """(op, value, slot) for `SLOT <cmp> <number>`, else None."""
    if cond.get("type") != "AstExprBinary" or cond.get("op") not in COMPARE_OPS:
        return None
    lhs = cond.get("left") or {}
    rhs = cond.get("right") or {}
    if lhs.get("type") != "AstExprLocal" or rhs.get("type") != "AstExprConstantNumber":
        return None
    val = rhs.get("value")
    if isinstance(val, bool) or not isinstance(val, (int, float)):
        return None
    return (cond.get("op"), val, (lhs.get("local") or {}).get("name"))

def _arm_source(source, offsets, node, next_loc):
    """The arm's own source: from its `if` up to the next arm (or the while)."""
    start = _loc_key(node.get("location", ""))
    end = _loc_key(next_loc) if next_loc else None
    if end is None or end <= start:
        return source[_offset(source, offsets, start[0], start[1]):][:1200]
    return source[_offset(source, offsets, start[0], start[1]):
                  _offset(source, offsets, end[0], end[1])]

def _offset(source, offsets, line, col):
    if line < 0 or line >= len(offsets):
        return 0
    return offsets[line] + col

def build_isa(source):
    """
    The dispatch tables for one recovered stage.

    A stage has **several** dispatch loops, not one: on the sampled build the
    hottest one (the loop the sandbox trace instruments, tags 8/13/29/71/102)
    and the largest one (state slot `g`, 47 arms) are different functions with
    different tag sets. So every chain gets its own table, and the widest is
    also returned at the top level as the primary one.

    Per table: {"state": var, "arms": int, "tags": {tag: {"count", "targets",
    "body"}}}. `body` is the arm's source so the caller can print the
    instruction's real meaning instead of guessing at one.
    """
    if not source:
        return {"state": None, "tags": {}, "interpreter_arms": 0,
                "step_wrapper": False, "interpreters": []}

    import luauast
    offsets = [0]
    for _line in source.split("\n"):
        offsets.append(offsets[-1] + len(_line) + 1)

    chains = find_interpreters(source)
    tables = []
    for key, arms, state in chains:
        texts = []
        for i, (cmp_pair, node, loc) in enumerate(arms):
            nxt = arms[i + 1][2] if i + 1 < len(arms) else None
            texts.append((cmp_pair, _arm_source(source, offsets, node, nxt)))
        reg_index = find_register_index([t for _tag, t in texts])
        tags = {}
        for cmp_pair, arm_src in texts:
            tag = tag_key(cmp_pair[0], cmp_pair[1])
            targets = _targets(arm_src, state)
            label, feats = classify(arm_src, reg_index)
            entry = tags.get(tag)
            if entry is None:
                tags[tag] = {"count": 1, "targets": targets,
                             "label": label, "features": feats,
                             "body": arm_src.strip()[:600]}
            else:
                entry["count"] += 1
                for t in targets:
                    if t not in entry["targets"]:
                        entry["targets"].append(t)
        tables.append({"state": state, "arms": len(texts), "tags": tags,
                       "register_index": reg_index, "key": key})

    tables.sort(key=lambda t: -t["arms"])

    result = {
        "state": None, "tags": {}, "interpreter_arms": 0,
        "step_wrapper": False,
        "interpreters": tables,
    }
    result["step_wrapper"] = bool(
        re.search(r"repeat\s+\w+,\w+,\w+,\w+\s*=\s*\w+:\w+\(", source)
    ) and "until false" in source

    if tables:
        primary = tables[0]
        result["state"] = primary["state"]
        result["tags"] = primary["tags"]
        result["interpreter_arms"] = primary["arms"]
    return result

def render_isa(isa):
    """Human-readable dispatch tables, for the top of a result file."""
    if not isa:
        return ""
    tables = isa.get("interpreters") or []
    if not tables:

        return ""
    lines = ["-- Luraph v14 dispatch tables (recovered from the decrypted stage)"]
    if isa.get("step_wrapper"):
        lines.append("-- step wrapper: repeat a,b,c,d=x:y(...) until false  (-2 = halt)")
    if len(tables) > 1:
        lines.append("-- %d dispatch chains in this stage; a tag means a different"
                     " instruction in each" % len(tables))
    for t in tables:
        lines.append("")
        lines.append("-- state slot %s, %d arms%s"
                     % (t["state"], t["arms"],
                        (", registers at [%s]" % t["register_index"])
                        if t.get("register_index") is not None else ""))
        for tag, info in sorted(t["tags"].items(), key=lambda kv: -kv[1]["count"]):
            tgt = ", ".join(info["targets"]) if info["targets"] else "-"
            lines.append("--   %-10s %-16s seen %-5d next: %s"
                         % (tag, info.get("label", "?"), info["count"], tgt))
            feats = info.get("features") or []
            if len(feats) > 1:
                lines.append("--       %s" % " ".join(feats))
    lines.append("")
    return "\n".join(lines) + "\n"
