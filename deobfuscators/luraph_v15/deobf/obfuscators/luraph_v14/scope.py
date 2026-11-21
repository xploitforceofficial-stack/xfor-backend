"""
Scope-aware operand injection for Luraph v14 dispatch loops.

Why this exists: the sandbox trace carries the dispatch tag and nothing else, so
there are no operands and nothing to lift from. Getting operands means knowing
the sibling locals at each dispatch site. Doing that with a pattern fails - a
non-greedy span crosses function boundaries in this layout, injects out-of-scope
names, and the stage stops running (measured: 3322 traced operations -> 0).

So resolve scope on the AST. This does NOT reimplement that: the scope walk,
the node iteration and the offset-accurate insertion all come from
`obfuscators.ironbrew1.instrument`, which already does them and is what the
ironbrew1 capture run relies on. All this module adds is knowledge of v14's
dispatch shape:

    while true do
      if Q==8.0 then ... elseif Q==102.0 then ...
    end

ironbrew1's `dispatch_loop` looks for a `while true do` whose first statement is
an indexed assignment; v14's first statement is an if/elseif equality chain on
a state slot. Same insertion machinery, different shape.

The hook is (I, _p, _y, L, O, V, f, e): it records I as the op and L..e as
a..e, and drops _p/_y. So operands are passed as (state, nil, nil, op1..op5) -
the padding is load-bearing, and passing them positionally silently discards the
frame that holds the register file.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
for _p in (os.path.dirname(os.path.dirname(HERE)), HERE):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import luauast
from obfuscators.ironbrew1 import instrument

TRACE = "__LPH_REG_TRACE__"
MAX_OPERANDS = 5

SPIN_SNIPPET = " __SPIN.n=__SPIN.n+1;if __SPIN.n>=__SPIN.step then __SPIN.f()end; "

def inject_spin(text, snippet=SPIN_SNIPPET):
    """Plant `snippet` at every dispatch-loop head in `text`.

    Returns (new_text, head_count). `text` comes back unchanged when it will
    not parse or has no dispatch loops - never a broken chunk. The default
    snippet needs CFG.spin set at runtime (the plugin forces it), otherwise
    the chunk errors on its first iteration; a diagnostic snippet with no
    runtime needs (e.g. a dispatch cap that errors)     works unconditionally.
    """
    try:
        root = luauast.parse(text)
    except Exception:
        return text, 0
    loops = find_dispatch_loops(root)
    if not loops:
        return text, 0
    edits = []
    for chain_id, (_state, _tags, first, _ops) in enumerate(loops, start=1):
        line, col = instrument.loc_start(first["location"])
        snip = snippet(chain_id, _state, _tags, first, _ops) if callable(snippet) else snippet
        edits.append((line, col, snip))
    patched = instrument.insert_at(text, edits)
    try:
        luauast.parse(patched)
    except Exception:
        return text, 0
    return patched, len(edits)

def inject_spin_all(text, snippet=SPIN_SNIPPET, conditional=False, repeats=False):
    """Plant `snippet` at the head of every `while` loop in `text`.

    inject_spin covers only if-chain-first dispatch loops, but the program
    itself runs in fetch loops that never match. Those silent loops are what
    stalls the run: without a step counter the harness cannot tell progress
    from a spin. `conditional` also covers `while <cond> do` loops, and
    `repeats` the `repeat ... until false` ones - v14 builds differ in which
    shape the dispatch loop takes (14.7 has both, and spins in the repeat
    while its `while true do` heads are instrumented and idle). Returns
    (new_text, head_count); `text` comes back unchanged on parse failure -
    never a broken chunk.
    """
    try:
        root = luauast.parse(text)
    except Exception:
        return text, 0
    edits = []
    for node in instrument.iter_nodes(root):
        if node.get("type") == "AstStatRepeat":
            if not repeats:
                continue
            loop = node
        elif node.get("type") == "AstStatWhile":
            c = node.get("condition") or {}
            if not conditional and not (c.get("type") == "AstExprConstantBool"
                                        and c.get("value")):
                continue
            loop = node
        else:
            continue
        body = (loop.get("body") or {}).get("body") or []
        if not body:
            continue
        first = body[0]
        if "location" not in first:
            continue
        line, col = instrument.loc_start(first["location"])
        snip = snippet(node) if callable(snippet) else snippet
        edits.append((line, col, snip))
    if not edits:
        return text, 0
    patched = instrument.insert_at(text, edits)
    try:
        luauast.parse(patched)
    except Exception:
        return text, 0
    return patched, len(edits)

def if_chain(node):
    """
    [(op, value, slot)] for an if/elseif chain on one slot, else [].

    Delegates to isa so there is ONE notion of what a dispatch arm is. The v14
    interpreters branch on ranges as well as equality (`elseif g<=2.0`,
    `elseif g<101.0 and g>30.0`), so a matcher that only knows `==` finds 22
    chains out of 194 and misses the ones that run the program.
    """
    from obfuscators.luraph_v14 import isa
    return isa._arm_chain(node)

def v14_dispatch_loop(node):
    """
    (state, [tags], first statement) if `node` is a v14 dispatch loop, else None.

    A dispatch loop is `while true do` whose first statement is an if/elseif
    equality chain, and where every arm tests the same state slot. Matching on
    the while node rather than on a function body means top-level loops and
    loops nested in blocks are found too, not just ones that sit directly in a
    function's statement list.
    """
    if node.get("type") != "AstStatWhile":
        return None
    c = node.get("condition") or {}
    if not (c.get("type") == "AstExprConstantBool" and c.get("value")):
        return None
    body = (node.get("body") or {}).get("body") or []
    if not body or body[0].get("type") != "AstStatIf":
        return None
    chain = if_chain(body[0])
    if not chain:
        return None
    states = {c[2] for c in chain}
    if len(states) != 1:
        return None
    return states.pop(), [c[1] for c in chain], body[0]

def find_dispatch_loops(root):
    """
    [(loop node, state, [tags], first-statement node, [operand names])].

    Walks every node in the tree. The decrypted stage is
    `return({f = function() ... end})`, so the interpreters live inside a
    table-constructor expression - `instrument.iter_nodes` descends into those,
    where a statement-only walk finds nothing.
    """
    found = []
    for node in instrument.iter_nodes(root):
        hit = v14_dispatch_loop(node)
        if not hit:
            continue
        _state, tags, first = hit
        state = _state

        visible = instrument.visible_at(root, first) or []
        names = []
        for info in visible:
            n = info.get("name") if isinstance(info, dict) else info
            if n and n != state and n not in names:
                names.append(n)
        found.append((state, tags, first, names[:MAX_OPERANDS]))
    return found

def _register_slot_for(source, offsets, first_stmt):
    """
    (name, index) of THIS loop's register file, or (None, None).

    Measured from this loop's own arms, via isa's own measurement, so the slot
    and the tag list always come from the same text. Per site rather than from
    isa's chain tables: those are keyed by (function, state), and two sites in
    one function would otherwise share a table and report each other's slot.
    """
    from obfuscators.luraph_v14 import isa
    arms = isa._arm_chain(first_stmt)
    if not arms:
        return None, None
    texts = []
    for i, (_op, _val, _state, node) in enumerate(arms):
        nxt = arms[i + 1][3].get("location") if i + 1 < len(arms) else None
        texts.append(isa._arm_source(source, offsets, node, nxt))
    return isa.find_register_slot(texts)

def inject(text, limit=None, debug=False):
    """
    Rewrite `text` so every dispatch ARM records itself, not just the loop head.

    Instrumenting the top of the dispatch loop gives one record per loop
    *iteration* with the state slot's value, which is not the program: the value
    a slot takes is a tag the interpreter branches on, and consecutive records
    collapse many instructions into one. Instrumenting the start of each arm
    instead gives one record per *executed instruction*, carrying the arm's own
    tag as a constant, plus the register file. Diffing consecutive records is
    then the deobfuscated instruction stream.

    The loop-head probe is kept too: it is what shows the state slot cycling.

    Returns (new_text, [{"state","tags","operands","chain","registerIndex",
    "registerName","registerOperand","armCount"}]). `text` comes back unchanged
    when there is nothing to do or the source will not parse - never a broken
    chunk.
    """
    try:
        root = luauast.parse(text)
    except Exception:
        return text, []

    loops = find_dispatch_loops(root)
    if not loops:
        return text, []
    if limit:
        loops = loops[:limit]

    from obfuscators.ironbrew1 import instrument as _inst
    offsets = [0]
    for _line in text.split("\n"):
        offsets.append(offsets[-1] + len(_line) + 1)

    def pad(args, want):
        out = list(args) + ["nil"] * (want - len(args))
        return out[:want]

    def probe(*vals):

        return " " + TRACE + "(%s); " % ",".join(vals)

    edits = []
    info = []
    for chain_id, (state, tags, first, ops) in enumerate(loops, start=1):
        line, col = _inst.loc_start(first["location"])
        operands = list(ops)
        reg_name, reg_index = _register_slot_for(text, offsets, first)
        reg_expr = "%s[%d]" % (reg_name, reg_index) if reg_name is not None else None

        head_args = ([reg_expr] if reg_expr else []) + operands[1:]
        edits.append((line, col, probe(
            state, str(chain_id), "nil", *pad(head_args, MAX_OPERANDS - 1))))

        from obfuscators.luraph_v14 import isa
        arms = isa._arm_chain(first)
        arm_count = 0
        for op, val, _st, node in arms:
            then = node.get("thenbody") or {}
            stmts = then.get("body") or []
            if not stmts:
                continue
            al, ac = _inst.loc_start(stmts[0]["location"])
            arm_args = [reg_expr] if reg_expr else []

            edits.append((al, ac, probe(
                isa._fmt_num(val), str(chain_id), "nil",
                *pad(arm_args, MAX_OPERANDS - 1))))
            arm_count += 1

        info.append({"state": state, "tags": tags, "operands": operands,
                     "chain": chain_id, "registerIndex": reg_index,
                     "registerName": reg_name,
                     "registerOperand": reg_expr,
                     "armCount": arm_count})

    if not edits:
        return text, []
    patched = _inst.insert_at(text, edits)

    try:
        luauast.parse(patched)
    except Exception as e:
        sys.stderr.write("[scope] arm probes broke the stage (%s); retrying head-only\n"
                         % type(e).__name__)
        head_only = []
        for chain_id, (state, tags, first, ops) in enumerate(loops, start=1):
            line, col = _inst.loc_start(first["location"])
            operands = list(ops)
            reg_name, reg_index = _register_slot_for(text, offsets, first)
            reg_expr = "%s[%d]" % (reg_name, reg_index) if reg_name is not None else None
            head_args = ([reg_expr] if reg_expr else []) + operands[1:]
            head_only.append((line, col, probe(
                state, str(chain_id), "nil", *pad(head_args, MAX_OPERANDS - 1))))
        patched = _inst.insert_at(text, head_only)
        try:
            luauast.parse(patched)
        except Exception:
            sys.stderr.write("[scope] head-only patch also failed; running unpatched\n")
            return text, [dict(i, armCount=0) for i in info]
        for i in info:
            i["armCount"] = 0

    if debug:
        sys.stderr.write("[scope] instrumenting %d dispatch loop(s), %d probe(s)\n"
                         % (len(loops), len(edits)))
    return patched, info

def _cli(argv):
    """
    scope.py <in> <out>

    Instrument `in`, write the result to `out`, and print a one-line JSON
    summary on stdout: {"loops":n,"states":[...],"tags":{...},"inBytes":n,
    "outBytes":n,"ok":bool}. The host (deobfuscators/luraph_v14_deob.js) uses
    that to build the stage-patch manifest without parsing anything else.

    Exits non-zero if the source will not parse, and still copies the input
    through unchanged, so a caller can fall back to the unpatched stage.
    """
    import json
    if len(argv) < 3:
        sys.stderr.write("usage: scope.py <in> <out>\n")
        return 2
    src_path, out_path = argv[1], argv[2]
    with open(src_path, encoding="utf-8", errors="replace") as f:
        src = f.read()

    ok = True
    try:
        out, info = inject(src)
    except Exception as e:
        sys.stderr.write("[scope] injection failed: %s: %s\n" % (type(e).__name__, e))
        out, info, ok = src, [], False

    with open(out_path, "w", encoding="utf-8", newline="") as f:
        f.write(out)

    states = {}
    for i in info:
        states[i["state"]] = states.get(i["state"], 0) + 1

    labels = {}
    try:
        from obfuscators.luraph_v14 import isa
        tables = isa.build_isa(src).get("interpreters") or []
    except Exception:
        tables = []
    for i in info:
        want = {str(t) for t in i["tags"]}
        best = None
        for t in tables:
            have = {str(k) for k in t["tags"]}
            if want and want <= have:
                if best is None or len(t["tags"]) < len(best["tags"]):
                    best = t
        if best is None:
            continue
        labels[str(i["chain"])] = {
            "state": best["state"],
            "registerIndex": best.get("register_index"),
            "arms": len(want),
            "tags": {str(k): {"label": v.get("label"),
                              "features": v.get("features"),
                              "targets": v.get("targets")}
                     for k, v in best["tags"].items() if str(k) in want},
        }

    summary = {
        "ok": ok,
        "loops": len(info),
        "states": states,
        "tags": {str(i["state"]): i["tags"] for i in info},
        "operands": {str(i["state"]): i["operands"] for i in info},
        "chainTags": {str(i["chain"]): i["tags"] for i in info},
        "chainLabels": labels,
        "inBytes": len(src.encode("utf-8", "replace")),
        "outBytes": len(out.encode("utf-8", "replace")),
    }
    sys.stdout.write(json.dumps(summary) + "\n")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(_cli(sys.argv))
