"""Walk A[49]'s dispatch tree and emit the code each opcode P actually runs.

A[49] is a binary search over `local P = t[G]`, but the obfuscator buried it in
constant junk: `local M = 75` is fixed, so every `M == k` test for k ~= 75 is
constant, and the real dispatch sits in the branch M == 75 selects. This tool
parses the if-tree, constant-folds the M tests, evaluates the P tests for a
concrete opcode, and prints the straight-line code that opcode reaches.

Output: tools/work/opcodes/<P>.lua for every opcode seen in op.tsv.
"""
import pathlib
import re

WORK = pathlib.Path(__file__).resolve().parent / "work"
A49 = WORK / "a49_full.lua"
OUT = WORK / "opcodes"

OPENERS = ("function", "if", "while", "for", "repeat")
CLOSERS = ("end", "until")

def _after_string(s: str, i: int) -> int:
    q = s[i]
    i += 1
    while i < len(s):
        if s[i] == "\\":
            i += 2
            continue
        if s[i] == q:
            return i + 1
        i += 1
    return len(s)

def _skip_trivia(s: str, i: int) -> int:
    """Step over whitespace, semicolons, commas and comments."""
    n = len(s)
    while i < n:
        c = s[i]
        if c in " \t\r\n;,":
            i += 1
        elif s.startswith("--", i):
            j = s.find("\n", i)
            i = n if j < 0 else j + 1
        else:
            break
    return i

def _step(s: str, i: int) -> int:
    """Advance one lexical element; returns (index, word-or-empty)."""
    i = _skip_trivia(s, i)
    if i >= len(s):
        return i, ""
    c = s[i]
    if c in "\"'":
        return _after_string(s, i), ""
    if s.startswith("[[", i):
        j = s.find("]]", i)
        return (len(s) if j < 0 else j + 2), ""
    m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", s[i:])
    if m:
        return i + m.end(), m.group(0)
    return i + 1, ""

def read_until(s: str, i: int, stop) -> tuple:
    """Read a condition up to `stop` at bracket depth 0. Returns (text, index)."""
    start = i
    depth = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c in "\"'":
            i = _after_string(s, i)
            continue
        if s.startswith("--", i):
            j = s.find("\n", i)
            i = n if j < 0 else j + 1
            continue
        if c in "([{":
            depth += 1
            i += 1
            continue
        if c in ")]}":
            depth -= 1
            i += 1
            continue
        if depth == 0 and re.match(r"[A-Za-z_]", c):
            j, w = _step(s, i)
            if w == stop:
                return s[start:i].strip(), i
            i = j
            continue
        i += 1
    return s[start:].strip(), i

def read_block(s: str, i: int) -> tuple:
    """Read a then/else body up to our own elseif/else/end. Returns (text, index)."""
    start = i
    depth = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c in "\"'":
            i = _after_string(s, i)
            continue
        if s.startswith("--", i):
            j = s.find("\n", i)
            i = n if j < 0 else j + 1
            continue
        if re.match(r"[A-Za-z_]", c):
            pos = i
            j, w = _step(s, i)
            if w in OPENERS:
                depth += 1
                i = j
                continue
            if w in CLOSERS:
                depth -= 1
                if depth < 0:
                    return s[start:pos].strip(), pos
                i = j
                continue
            if depth == 0 and w in ("elseif", "else"):
                return s[start:pos].strip(), pos
            i = j
            continue
        i += 1
    return s[start:].strip(), i

class If:
    __slots__ = ("cond", "then", "other")

    def __init__(self, cond, then, other):
        self.cond = cond
        self.then = then
        self.other = other

def parse_if(s: str, i: int) -> tuple:
    """Parse `if C then B (elseif..|else..)? end`. Returns (If, index after)."""
    _j, _w = _step(s, i)
    cond, i = read_until(s, _j, "then")
    _j, _w = _step(s, i)
    then, i = read_block(s, _j)
    i = _skip_trivia(s, i)
    other = None
    if s.startswith("elseif", i):
        depth = 0
        start = i
        n = len(s)
        while i < n:
            c = s[i]
            if c in "\"'":
                i = _after_string(s, i)
                continue
            if re.match(r"[A-Za-z_]", c):
                j, w = _step(s, i)
                if w in OPENERS:
                    depth += 1
                elif w in CLOSERS:
                    depth -= 1
                    if depth < 0:
                        i = j
                        break
                i = j
                continue
            i += 1
        tail = s[start:i]
        other = "if " + tail[len("elseif") :] + " end"
    elif s.startswith("else", i):
        _j, _w = _step(s, i)
        other, i = read_block(s, _j)
    i = _skip_trivia(s, i)
    if s.startswith("end", i):
        _j, _w = _step(s, i)
        i = _j
    return If(cond, then, other), i

def split_top(body: str):
    """Split a body into statement runs and the top-level if-blocks."""
    items = []
    depth = 0
    i = 0
    buf_start = 0
    n = len(body)
    while i < n:
        c = body[i]
        if c in "\"'":
            i = _after_string(body, i)
            continue
        if body.startswith("--", i):
            j = body.find("\n", i)
            i = n if j < 0 else j + 1
            continue
        if re.match(r"[A-Za-z_]", c):
            pos = i
            j, w = _step(body, i)
            if depth == 0 and w == "if":
                if body[buf_start:pos].strip():
                    items.append(("stmt", body[buf_start:pos].strip()))
                node, i = parse_if(body, pos)
                items.append(("if", node))
                buf_start = i
                continue
            if w in OPENERS:
                depth += 1
            elif w in CLOSERS:
                depth -= 1
            i = j
            continue
        i += 1
    if body[buf_start:].strip():
        items.append(("stmt", body[buf_start:].strip()))
    return items

def m_value(cond: str):
    """Fold a `M == k` / `M ~= k` test, given M is fixed at 75."""
    m = re.fullmatch(r"M\s*(==|~=)\s*(\d+)(?:\.0+)?", cond.strip())
    if not m:
        return None
    is_eq = m.group(1) == "=="
    num = int(m.group(2))
    return (75 == num) if is_eq else (75 != num)

JUNKCONSTS = {}

def junk_value(cond: str):
    for name, val in JUNKCONSTS.items():
        m = re.fullmatch(r"%s\s*(==|~=)\s*(\d+)(?:\.0+)?" % re.escape(name), cond.strip())
        if m:
            is_eq = m.group(1) == "=="
            num = int(m.group(2))
            return (val == num) if is_eq else (val != num)
    return None

ZSTATE = {}

def zterm(term):
    """Resolve a z[k] literal/number/string/bool/nil to a value or None."""
    term = term.strip()
    m = re.fullmatch(r"z\[(\d+)\]", term)
    if m:
        e = ZSTATE.get(int(m.group(1)))
        if e is None:
            return None
        tp, v = e
        if tp == "number":
            try:
                return ("num", float(v))
            except (TypeError, ValueError):
                return None
        if tp == "string":
            return ("str", v)
        if tp == "boolean":
            return ("bool", v == "true")
        if tp == "nil":
            return ("nil", None)
        return (tp, v)
    if re.fullmatch(r"-?\d+(?:\.\d+)?", term):
        try:
            return ("num", float(term))
        except ValueError:
            return None
    if len(term) >= 2 and term[0] == '"' and term[-1] == '"':
        return ("str", term[1:-1])
    if term == "true":
        return ("bool", True)
    if term == "false":
        return ("bool", False)
    if term == "nil":
        return ("nil", None)
    return None

def ztruthy(v):
    if v is None:
        return None
    if v[0] == "nil":
        return False
    if v[0] == "bool":
        return v[1]
    return True

def zcmp(a, op, b):
    if a is None or b is None:
        return None
    if op in ("==", "~="):
        if a[0] != b[0]:
            eq = False
        elif a[0] in ("num", "str", "bool"):
            eq = (a[1] == b[1])
        else:
            eq = (a[1] == b[1])
        return eq if op == "==" else (not eq)
    if a[0] == "num" and b[0] == "num":
        x, y = a[1], b[1]
        return {"<": x < y, ">": x > y, "<=": x <= y, ">=": x >= y}[op]
    if a[0] == "str" and b[0] == "str":
        x, y = a[1], b[1]
        return {"<": x < y, ">": x > y, "<=": x <= y, ">=": x >= y}[op]
    return None

def split_op(s, sep):
    """Split on sep at depth 0, respecting strings and brackets."""
    parts, buf = [], []
    depth = 0
    q = None
    i = 0
    while i < len(s):
        ch = s[i]
        if q:
            buf.append(ch)
            if ch == "\\" and i + 1 < len(s):
                buf.append(s[i + 1])
                i += 2
                continue
            if ch == q:
                q = None
            i += 1
            continue
        if ch in ("\"", "'"):
            q = ch
            buf.append(ch)
            i += 1
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if depth == 0 and s.startswith(sep, i):
            parts.append("".join(buf))
            buf = []
            i += len(sep)
            continue
        buf.append(ch)
        i += 1
    parts.append("".join(buf))
    return parts

def zeval(s):
    """Evaluate a z-state/literal expression to a value or None."""
    s = s.strip()
    while True:
        m = re.fullmatch(r"not\s*\((.*)\)", s, re.S) or re.fullmatch(r"not\s+(.+)", s, re.S)
        if m:
            v = zeval(m.group(1))
            t = ztruthy(v)
            return ("bool", not t) if t is not None else None
        break
    m = re.fullmatch(r"-\s*(.+)", s, re.S)
    if m:
        v = zeval(m.group(1))
        if v is not None and v[0] == "num":
            return ("num", -v[1])
        return None

    depth = 0
    q = None
    for i, ch in enumerate(s):
        if q:
            if ch == "\\":
                continue
            if ch == q:
                q = None
            continue
        if ch in ("\"", "'"):
            q = ch
            continue
        if ch in "([{":
            depth += 1
            continue
        if ch in ")]}":
            depth -= 1
            continue
        if depth == 0:
            if s.startswith("and", i) and not re.match(r"[A-Za-z0-9_]", s[i - 1] if i else " ") \
                    and not re.match(r"[A-Za-z0-9_]", s[i + 3] if i + 3 < len(s) else " "):
                a = zeval(s[:i])
                if a is None:
                    return None
                ta = ztruthy(a)
                if ta is None:
                    return None
                if not ta:
                    return a
                return zeval(s[i + 3:])
            if s.startswith("or", i) and not re.match(r"[A-Za-z0-9_]", s[i - 1] if i else " ") \
                    and not re.match(r"[A-Za-z0-9_]", s[i + 2] if i + 2 < len(s) else " "):
                a = zeval(s[:i])
                if a is None:
                    return None
                ta = ztruthy(a)
                if ta is None:
                    return None
                if ta:
                    return a
                return zeval(s[i + 2:])
    for op in ("==", "~=", "<=", ">=", "<", ">"):
        parts = split_op(s, op)
        if len(parts) == 2 and parts[0].strip() != "" and parts[1].strip() != "":
            if op in ("<", ">"):
                if parts[1].lstrip().startswith("=") or parts[0].rstrip().endswith(("=", "~", "<", ">")):
                    continue
            a = zeval(parts[0])
            b = zeval(parts[1])
            r = zcmp(a, op, b)
            if r is not None:
                return ("bool", r)
            return None
    if re.fullmatch(r"\(.*\)", s, re.S):
        inner = s[1:-1]

        depth = 0
        qq = None
        ok = True
        for ch in inner:
            if qq:
                if ch == qq:
                    qq = None
                continue
            if ch in ("\"", "'"):
                qq = ch
                continue
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth < 0:
                    ok = False
                    break
        if ok and depth == 0:
            return zeval(inner)
    return zterm(s)

def zfold_cond(cond: str):
    """Decide a dispatch-table test against the captured z-state."""
    v = zeval(cond.strip())
    if v is None:
        return None
    return ztruthy(v)

def eval_p(cond: str, P: int) -> bool:
    c = cond.strip()
    neg = False
    m = re.match(r"not\s*\((.*)\)\s*$", c, re.S)
    if m and OPVAR in m.group(1):
        neg = True
        c = m.group(1)
    m = re.search(r"%s\s*(<|<=|>|>=|==|~=)\s*(\d+)" % re.escape(OPVAR), c)
    if not m:
        raise ValueError(cond)
    op, num = m.group(1), int(m.group(2))
    res = {
        "<": P < num,
        "<=": P <= num,
        ">": P > num,
        ">=": P >= num,
        "==": P == num,
        "~=": P != num,
    }[op]
    return (not res) if neg else res

def is_p_test(cond: str) -> bool:
    return re.search(r"\b%s\b\s*(<|<=|>|>=|==|~=)" % re.escape(OPVAR), cond) is not None

def has_p_test(text: str) -> bool:
    return re.search(r"\b%s\b\s*(<|<=|>|>=|==|~=)" % re.escape(OPVAR), text) is not None

DEFAULT_RUNTIME_NAMES = (
    "d|i|w|D|f|O|z|G|t|j|Z|K|T|q|n|g|b|v|e|h|o|a|S|L|U|W|E|X|N|r|u|I|C|Y|c|F|H|l"
)
OPVAR = "P"
RUNTIME_NAMES = re.compile(r"\b(%s)\b" % DEFAULT_RUNTIME_NAMES)
JUNKCONSTS = {}
JUNKDECLS = ["local M=75"]

ASSIGNED: set = set()

ASSIGNED_RUNTIME: set = set()

def note_assign(stmt: str) -> None:
    """Record names bound earlier in this leaf; tests on them are runtime values."""
    pat = r"(?<![=~<>])([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*=(?![=~<>])"
    for group in re.findall(pat, stmt):
        for name in group.split(","):
            name = name.strip()
            if name:
                ASSIGNED.add(name)

def is_runtime_test(cond: str) -> bool:
    if RUNTIME_NAMES.search(cond) is not None:
        return True
    if not ASSIGNED_RUNTIME:
        return False
    return any(re.search(r"\b%s\b" % re.escape(n), cond) for n in ASSIGNED_RUNTIME if n in ASSIGNED)

TRACE: list = []

def fold(body: str, P: int, notes: list) -> list:
    """Return the statements `body` executes for opcode P, junk folded away."""
    out: list = []
    for kind, payload in split_top(body):
        if kind == "stmt":
            out.append(payload)
            note_assign(payload)
            continue
        node: If = payload
        mv = m_value(node.cond)
        if mv is not None:
            branch = node.then if mv else node.other
            if branch:
                out.extend(fold(branch, P, notes))
            continue
        jv = junk_value(node.cond)
        if jv is not None:
            notes.append(f"junkfold {node.cond.strip()} -> {'then' if jv else 'else'}")
            branch = node.then if jv else node.other
            if branch:
                out.extend(fold(branch, P, notes))
            continue
        if ZSTATE:
            zv = zfold_cond(node.cond)
            if zv is not None:
                notes.append(f"zfold {node.cond.strip()} -> {'then' if zv else 'else'}")
                branch = node.then if zv else node.other
                if branch:
                    out.extend(fold(branch, P, notes))
                continue
        if is_p_test(node.cond):
            taken = eval_p(node.cond, P)
            TRACE.append((node.cond.strip(), taken))
            branch = node.then if taken else node.other
            if branch:
                out.extend(fold(branch, P, notes))
            continue

        then_spine = has_p_test(node.then)
        other_spine = bool(node.other) and has_p_test(node.other)
        if is_runtime_test(node.cond):
            notes.append(f"RUNTIME-OPAQUE {node.cond.strip()}")
            out.append(f"if {node.cond.strip()} then")
            out.extend(fold(node.then, P, notes))
            if node.other:
                out.append("else")
                out.extend(fold(node.other, P, notes))
            out.append("end")
        elif other_spine and not then_spine:
            notes.append(f"opaque {node.cond.strip()} -> else")
            out.extend(fold(node.other, P, notes))
        elif then_spine or not node.other:
            notes.append(f"opaque {node.cond.strip()} -> then")
            out.extend(fold(node.then, P, notes))
        else:

            notes.append(f"AMBIGUOUS {node.cond.strip()}")
            out.append(f"if {node.cond.strip()} then")
            out.extend(fold(node.then, P, notes))
            if node.other:
                out.append("else")
                out.extend(fold(node.other, P, notes))
            out.append("end")
    return out

TAIL_MARK = "G+=1.0"

def clean(stmts) -> list:
    """Drop the junk declaration, empty statements and the loop epilogue."""
    text = "\n".join(stmts)
    i = text.find(TAIL_MARK)
    if i >= 0:
        text = text[:i]
    for decl in JUNKDECLS:
        text = text.replace(decl + ";", "").replace(decl, "")
    text = re.sub(r";{2,}", ";", text)
    text = re.sub(r"\A[\s;]+", "", text)
    text = re.sub(r";(?=\s*(?:local|for|while|repeat|if|return|until)\b)", ";\n", text)
    text = re.sub(r"end;\s*(?=\S)", "end;\n", text)
    return [
        re.sub(r"\A[\s;]+", "", ln.strip())
        for ln in text.split("\n")
        if re.sub(r"\A[\s;]+", "", ln.strip()) and set(ln.strip()) != {";"}
    ]

def balance(text: str) -> int:
    """Net block depth of a leaf: 0 means the emitted Lua parses.

    `for`/`while` consume the following `do`, so that `do` must not be counted
    twice - `pending` tracks it.
    """
    depth = 0
    pending = False
    for tok in re.findall(r"[A-Za-z_]\w*", text):
        if tok in ("for", "while"):
            depth += 1
            pending = True
        elif tok == "do":
            if pending:
                pending = False
            else:
                depth += 1
        elif tok in ("if", "function", "repeat"):
            depth += 1
        elif tok in ("end", "until"):
            depth -= 1
    return depth

def rebalance(lines) -> list:
    """The fold can leave a stray closer (the leaf sits inside `J=function`,
    so its own `end` sometimes leaks). Drop trailing `end`s while the depth is
    negative and pad it while positive."""
    d = balance("\n".join(lines))
    while d < 0 and lines:
        hit = False
        for i in range(len(lines) - 1, -1, -1):
            if lines[i].strip() in ("end", "end;"):
                del lines[i]
                d += 1
                hit = True
                break
        if not hit:
            break
    while d > 0:
        lines.append("end")
        d -= 1
    return lines

def trim_tail(lines):
    """Drop `end` tokens left over by folded dead branches.

    Folding replaces a decision with only its taken side, so the discarded side's
    closing `end` can survive. Walk the tail and remove unmatched closers; the
    caller's `clean()` already re-balances anything still open.
    """
    lines = list(lines)
    while balance("\n".join(lines)) < 0:
        removed = False
        for i in range(len(lines) - 1, -1, -1):
            ln = lines[i]
            stripped = re.sub(r"\bend\b\s*;?\s*$", "", ln).rstrip()
            if stripped == ln or stripped.endswith("else") \
                    or re.search(r"\b(else|elseif)\b\s*$", stripped):
                continue
            lines[i] = stripped
            removed = True
            break
        if not removed:
            break
    return lines

def main() -> int:
    global OPVAR, RUNTIME_NAMES, OUT, JUNKCONSTS, JUNKDECLS
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", default=str(WORK))
    ap.add_argument("--src", default=None,
                    help="stage/dispatch source file (default <work>/a49_full.lua)")
    ap.add_argument("--fetch", default="local P=(t[G]);",
                    help="dispatch fetch-head anchor text")
    ap.add_argument("--opvar", default="P", help="opcode variable name")
    ap.add_argument("--out", default=None, help="leaves dir (default <work>/opcodes)")
    ap.add_argument("--opts", default="op.tsv", help="op-trace filename in workdir")
    ap.add_argument("--chains", default="chains_post.tsv",
                    help="chains filename in workdir (fallback chains.tsv)")
    ap.add_argument("--runtimenames", default=DEFAULT_RUNTIME_NAMES,
                    help="| separated runtime identifier list")
    ap.add_argument("--junkconsts", default="",
                    help="extra junk folds name=value,name=value (e.g. D=172)")
    ap.add_argument("--junkdecls", default="",
                    help="extra junk declarations to drop, ;-separated")
    ap.add_argument("--zstate", default="",
                    help="TSV with runtime z-state (slot, type, value) for folding")
    ap.add_argument("--assignednames", default="",
                    help="|-separated leaf-local names whose values are per-instruction")
    args = ap.parse_args()

    global OPVAR, RUNTIME_NAMES, OUT, JUNKCONSTS, JUNKDECLS, ZSTATE, ASSIGNED_RUNTIME
    OPVAR = args.opvar
    RUNTIME_NAMES = re.compile(r"\b(%s)\b" % args.runtimenames)
    ASSIGNED_RUNTIME = {n.strip() for n in args.assignednames.split("|") if n.strip()}
    ZSTATE = {}
    if args.zstate.strip():
        for line in pathlib.Path(args.zstate).read_text(encoding="utf-8").splitlines():
            parts = line.split("\t")
            if len(parts) == 3:
                try:
                    ZSTATE[int(parts[0])] = (parts[1], parts[2])
                except ValueError:
                    pass
        print(f"zstate slots: {len(ZSTATE)} from {args.zstate}")
    JUNKCONSTS = {}
    if args.junkconsts.strip():
        for pair in args.junkconsts.split(","):
            name, val = pair.split("=")
            JUNKCONSTS[name.strip()] = int(val)
    JUNKDECLS = ["local M=75"]
    if args.junkdecls.strip():
        JUNKDECLS += [d.strip() for d in args.junkdecls.split(";") if d.strip()]
    work = pathlib.Path(args.work)
    src = pathlib.Path(args.src) if args.src else work / "a49_full.lua"
    OUT = pathlib.Path(args.out) if args.out else work / "opcodes"
    body = src.read_text(encoding="utf-8")
    anchor = args.fetch
    body = body[body.index(anchor) + len(anchor):]

    seen = set()
    optp = work / args.opts
    if optp.exists():
        seen = set(
            int(line.split("\t")[1])
            for line in optp.read_text(encoding="utf-8").splitlines()
            if len(line.split("\t")) >= 2 and line.split("\t")[1].strip().lstrip('-').isdigit()
        )

    for cf in (args.chains, "chains.tsv"):
        try:
            raw_chains = (work / cf).read_bytes().decode("latin-1")
            for line in raw_chains.splitlines():
                parts = line.split("\t")
                if len(parts) == 9 and parts[2].strip().lstrip('-').isdigit():
                    seen.add(int(float(parts[2])))
            break
        except FileNotFoundError:
            continue
    seen = sorted(seen)
    OUT.mkdir(exist_ok=True)
    for old in OUT.glob("*.lua"):
        old.unlink()

    ambiguous = set()
    unbalanced = {}
    for P in seen:
        notes: list = []
        ASSIGNED.clear()
        out = fold(body, P, notes)
        for n in notes:
            if n.startswith("AMBIGUOUS"):
                ambiguous.add(P)
        lines = trim_tail(clean(out))

        if any(re.match(r"return\b", ln) for ln in lines):
            inc = re.compile(r"\A[A-Za-z_]\w*\s*\+=\s*[\d.]+\s*;?\Z")
            while lines and (inc.match(lines[-1]) or not lines[-1].strip()):
                lines.pop()
        bodytext = "\n".join(lines)
        depth = balance(bodytext)
        if depth:
            unbalanced[P] = depth
            notes.append(f"UNBALANCED depth={depth:+d}")
        header = f"-- opcode {P}"
        if notes:
            header += "\n-- " + "\n-- ".join(dict.fromkeys(notes))
        (OUT / f"{P:03d}.lua").write_text(
            header + "\n" + bodytext + "\n", encoding="utf-8"
        )

    print(f"wrote {len(seen)} leaves to {OUT}")
    print(f"ambiguous: {sorted(ambiguous)}")
    print(f"unbalanced: {unbalanced or 'none'}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
