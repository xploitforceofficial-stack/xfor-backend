"""Symbolic-execute Luraph v14 chains into exact user-level Luau (v1).

Reads tools/work/{chains.tsv,opcodes/*.lua} (+ optional f2chain.json), writes
<work>/simple.lua: one `local function chain_N(...)` per VM function with the
recovered statements (calls, returns, control flow on constant conditions).

Method: per chain, simulate the G program counter from slot 1 with an abstract
register file. Jumps on constant targets are followed; conditional jumps on
constant conditions fold; calls with resolvable func/args render as real Luau
(`print("heyy")`, `game:GetService("Players")`); unknown branch conditions or
complex decoder templates stop the path with an honest `-- [[partial]]`
marker (the dispatch-form lifted.lua still covers those chains fully).

Value model: num/str/bool/nil, global(name), table(id) with const keys,
upval(n), closure(chain), regs-alias K, unknown. Tables snapshot at use so
later mutations cannot rewrite an already-emitted call.

Usage: python tools/simplify14.py [workdir] [out.lua]
"""
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lift14 import (
    load_slots, load_leaves, clean_leaf, substitute, lua_quote, comment_safe,
)
import lift14

STEP_LIMIT = 200000
UNROLL_LIMIT = 8

class V:
    __slots__ = ("kind", "data")
    def __init__(self, kind, data=None):
        self.kind = kind
        self.data = data
    def __repr__(self):
        return "V(%s,%r)" % (self.kind, self.data)
    def __eq__(self, other):
        return isinstance(other, V) and self.kind == other.kind and self.data == other.data

def const(v):
    if v is True or v is False:
        return V("bool", v)
    if v is None:
        return V("nil")
    if isinstance(v, str):
        return V("str", v)
    return V("num", float(v))

UNK = V("unknown")

def is_const(v):
    return v.kind in ("num", "str", "bool", "nil")

def val_key(v):
    if v.kind == "num":
        f = v.data
        return ("n", int(f) if float(f).is_integer() else f)
    if v.kind in ("str", "bool", "global", "upval", "closure"):
        return (v.kind, v.data)
    if v.kind == "nil":
        return ("nil", 0)
    return None

class State:
    def __init__(self):
        self.regs = {}
        self.temps = {"Z": V("unknown", "env"), "W": V("num", 1.0), "T": V("num", 1.0)}
        self.tables = {}
        self.next_tid = 1
        self.upvals = {}
        self.approx = False

        self.chain = None
        self.upenv = None
        self.cmap = None

        self.assigned_r = set()
        self.assigned_t = set(("Z", "W", "T"))

    def copy(self):
        n = State()
        n.regs = dict(self.regs)
        n.temps = dict(self.temps)
        n.tables = {k: dict(v) for k, v in self.tables.items()}
        n.next_tid = self.next_tid
        n.upvals = dict(self.upvals)
        n.assigned_r = set(self.assigned_r)
        n.assigned_t = set(self.assigned_t)
        n.approx = self.approx
        n.chain = self.chain
        n.upenv = self.upenv
        n.cmap = self.cmap
        return n

    def new_table(self, init=None):
        tid = self.next_tid
        self.next_tid += 1
        self.tables[tid] = dict(init or {})
        return V("table", tid)

    def snapshot(self, v):
        """Freeze a value for emission (tables deep-copied one level)."""
        if v.kind == "table":
            return V("tablelit", dict(self.tables.get(v.data, {})))
        return v

def merge_states(a, b):
    """Join two path states; conflicts degrade to unknown (never wrong)."""
    m = State()
    m.next_tid = max(a.next_tid, b.next_tid)
    for k in set(a.regs) | set(b.regs):
        va, vb = a.regs.get(k), b.regs.get(k)
        if va is not None or vb is not None:
            m.regs[k] = va if va == vb else V("unknown", "merge")
    for k in set(a.temps) | set(b.temps):
        va, vb = a.temps.get(k), b.temps.get(k)
        if va is not None or vb is not None:
            m.temps[k] = va if va == vb else V("unknown", "merge")
    m.assigned_r = a.assigned_r | b.assigned_r
    m.assigned_t = (a.assigned_t | b.assigned_t) | {"Z", "W", "T"}
    m.approx = a.approx or b.approx
    m.chain = a.chain
    m.upenv = a.upenv
    m.cmap = a.cmap
    for k in set(a.upvals) | set(b.upvals):
        va, vb = a.upvals.get(k), b.upvals.get(k)
        m.upvals[k] = va if va == vb else V("unknown", "merge")
    kept = {}
    for tid in set(a.tables) & set(b.tables):
        if a.tables[tid] == b.tables[tid]:
            kept[tid] = dict(a.tables[tid])
    m.tables = kept

    live = set(kept)
    for k, v in list(m.regs.items()):
        if isinstance(v, V) and v.kind == "table" and v.data not in live:
            m.regs[k] = V("unknown", "merge")
    for k, v in list(m.temps.items()):
        if isinstance(v, V) and v.kind == "table" and v.data not in live:
            m.temps[k] = V("unknown", "merge")
    return m

def render_cond(cond, st):
    """Render a branch condition with resolved regs; None if not renderable.

    Only forks when every register in the condition holds a param, constant,
    global or upvalue reference -- anything else bails to partial instead of
    emitting code over unknown values.
    """

    out = []
    i = 0
    n = len(cond)
    while i < n:
        ch = cond[i]
        if ch in ("\"", "'"):
            j = i + 1
            while j < n:
                if cond[j] == "\\":
                    j += 2
                    continue
                if cond[j] == ch:
                    break
                j += 1
            out.append(cond[i:j + 1])
            i = j + 1
            continue
        m = re.match(r"\(d\)\[(\d+)\]|d\[(\d+)\]", cond[i:])
        if m:
            r = int(m.group(1) or m.group(2))
            v = st.regs.get(r)
            if v is None or v.kind not in ("num", "str", "bool", "nil",
                                           "global", "param", "upval", "closure"):
                return None
            if v.kind == "upval":
                return None
            out.append(render_val(v, st))
            i += m.end()
            continue
        m = re.match(r'Z\["([^"]*)"\]', cond[i:])
        if m:
            out.append(m.group(1))
            i += m.end()
            continue
        out.append(ch)
        i += 1
    text = "".join(out)

    if re.search(r"\bd\s*\[|\(d\)|[\s(]j\s*\[|[\s(]A\s*\[|\bM\b|[\s(]I\s*\[|\bt\b(?![\w])", text):
        return None
    return text.strip()

NUM_RE = re.compile(r"^-?(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d*)?(?:[eE][+-]?\d+)?)$")

def parse_num(s):
    s = s.replace("_", "")
    try:
        if s[:2].lower() in ("0x", "0b"):
            return float(int(s, 0))
        return float(s)
    except ValueError:
        return None

def unquote_lua(s):
    """Parse a \"...\" literal (decimal \\ddd escapes) to a python string."""
    if len(s) < 2 or s[0] != '"' or s[-1] != '"':
        return None
    body = s[1:-1]
    out = []
    i = 0
    while i < len(body):
        ch = body[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        i += 1
        if i >= len(body):
            return None
        e = body[i]
        if e == "n":
            out.append("\n")
        elif e == "r":
            out.append("\r")
        elif e == "t":
            out.append("\t")
        elif e in ("\\", '"', "'"):
            out.append(e)
        elif e == "a":
            out.append("\a")
        elif e == "b":
            out.append("\b")
        elif e == "f":
            out.append("\f")
        elif e == "v":
            out.append("\v")
        elif e == "u" and body[i:i + 2] == "u{":
            j = body.find("}", i)
            if j < 0:
                return None
            try:
                out.append(chr(int(body[i + 2:j], 16)))
            except ValueError:
                return None
            i = j + 1
            continue
        elif e.isdigit():
            m = re.match(r"\d{1,3}", body[i:])
            out.append(chr(int(m.group(0)) % 256))
            i += len(m.group(0))
            continue
        else:
            return None
        i += 1
    return "".join(out)

def bare_addr(s):
    s = (s or "").strip()
    if s.startswith("table: "):
        return s[7:]
    if s.startswith("function: "):
        return s[10:]
    return s

def num_or_str_key(v):
    if v.kind == "num" and float(v.data).is_integer():
        return str(int(v.data))
    if v.kind == "str":
        return v
    return None

def upenv_val(st, path):
    """Resolve an upvalue-env path (e.g. "0.4") against the entry snapshot."""
    e = (st.upenv or {}).get(path)
    if e is None:

        m = re.fullmatch(r"(.+)\.([^.]+)", path)
        if m and ((m.group(1) + "[box]") in (st.upenv or {})):
            st.approx = True
            return upenv_val(st, m.group(1) + "[box]")
        return V("upval", path)
    tp, v = e.get("tp"), e.get("v")
    if tp == "number":
        try:
            return V("num", float(v))
        except (TypeError, ValueError):
            return V("unknown", "upnum")
    if tp == "string":
        return V("str", v if isinstance(v, str) else str(v))
    if tp == "boolean":
        return V("bool", bool(v))
    if tp == "function":
        ch = (st.cmap or {}).get(bare_addr(v) if isinstance(v, str) else "")
        if ch is not None:
            return V("closure", ch)
        return V("unknown", "upfunc")
    if tp == "table":
        return V("unknown", "uptable")
    if path.endswith("[box]"):

        st.approx = True
        if tp == "number":
            try:
                return V("num", float(v))
            except (TypeError, ValueError):
                pass
        if tp == "string":
            return V("str", v if isinstance(v, str) else str(v))
        if tp == "boolean":
            return V("bool", bool(v))
        if tp == "function":
            ch = (st.cmap or {}).get(bare_addr(v) if isinstance(v, str) else "")
            if ch is not None:
                return V("closure", ch)
    return V("unknown", "up:" + str(tp))

def strip_parens(s):
    s = s.strip()
    while len(s) >= 2 and s[0] == "(" and s[-1] == ")":
        depth = 0
        ok = True
        for i, ch in enumerate(s):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0 and i < len(s) - 1:
                    ok = False
                    break
        if not ok or depth != 0:
            break
        s = s[1:-1].strip()
    return s

def split_top(s, sep):
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

def split_cmp(s):
    """Split a top-level comparison operator (quote/bracket aware)."""
    for op in ("==", "~=", "<=", ">=", "<", ">"):
        parts = split_top(s, op)
        if len(parts) != 2:
            continue
        a, b = parts[0].strip(), parts[1].strip()
        if not a or not b:
            continue
        if op in ("<", ">"):

            if b.startswith("=") or a.endswith(("=", "~", "<", ">")):
                continue
        return a, op, b
    return None

def eval_expr(s, st):
    s = strip_parens(s.strip())
    if s in ("nil",):
        return V("nil")
    if s == "true":
        return V("bool", True)
    if s == "false":
        return V("bool", False)
    if s == "...":
        return V("unknown", "varargs")
    if s.startswith('"'):
        u = unquote_lua(s)
        return V("str", u) if u is not None else V("unknown", "str?")
    if NUM_RE.match(s):
        n = parse_num(s)
        return V("num", n) if n is not None else UNK
    m = re.fullmatch(r"[dD]\[([^\]]+)\]", s) or re.fullmatch(r"\(d\)\[([^\]]+)\]", s)
    if m:
        idx = eval_expr(m.group(1), st)
        if idx.kind == "num" and float(idx.data).is_integer():
            r = int(idx.data)
            if r in st.assigned_r:
                return st.regs.get(r, V("nil"))
            return V("nil")
        return UNK
    m = re.fullmatch(r'Z\["([^"]*)"\]|\(Z\["([^"]*)"\]\)', s)
    if m:
        return V("global", m.group(1) or m.group(2))
    m = re.fullmatch(r"j\[(.+)\]\[(.+)\]", s)
    if m:
        ka = num_or_str_key(eval_expr(m.group(1), st))
        kb = num_or_str_key(eval_expr(m.group(2), st))
        if ka is not None and kb is not None:
            return upenv_val(st, "%s.%s" % (ka, kb))
        return V("unknown", "updyn")
    m = re.fullmatch(r"j\[(.+)\]", s)
    if m:
        ka = num_or_str_key(eval_expr(m.group(1), st))
        if ka is not None:
            return V("jenv", ka)
        return V("unknown", "updyn")
    if re.fullmatch(r"[A-Za-z_]\w*", s):
        if s in ("d", "K", "q", "n", "g", "T", "b", "v", "e", "h", "o", "a",
                 "S", "L", "U", "W", "E", "X", "N", "r", "u", "M", "P", "D_arr",
                 "t", "j", "Z", "A", "I", "J", "G", "H", "F", "C", "Y", "c", "Ff"):
            if s == "d":
                return V("regs",)
            if s == "K" and isinstance(st.temps.get("K"), V) and st.temps["K"].kind == "regs":
                return V("regs",)
            if s in st.assigned_t:
                return st.temps.get(s, V("nil"))
            return V("nil")
        return V("unknown", "name:" + s)
    if s == "K" :
        return st.temps.get("K", UNK)

    c = split_cmp(s)
    if c:
        a, op, b = c
        r = cmp_vals(eval_expr(a, st), op, eval_expr(b, st))
        if r is not None:
            return V("bool", r)
        return UNK

    if s.endswith("]"):
        depth = 0
        q = None
        for i in range(len(s) - 1, -1, -1):
            ch = s[i]
            if q:
                if ch == q:
                    q = None
                continue
            if ch in ("\"", "'"):
                q = ch
                continue
            if ch == "]":
                depth += 1
            elif ch == "[":
                depth -= 1
                if depth == 0:
                    base = eval_expr(s[:i], st)
                    key = eval_expr(s[i + 1:-1], st)
                    return index_val(base, key, st)

    for op in ("..",):
        parts = split_top(s, op)
        if len(parts) == 2:
            a = eval_expr(parts[0], st)
            b = eval_expr(parts[1], st)
            if a.kind == "str" and b.kind == "str":
                return V("str", a.data + b.data)
            return UNK
    for op in ("+", "-", "*", "/", "%", "^"):
        parts = split_top(s, op)
        if len(parts) == 2 and parts[0].strip() != "":
            a = eval_expr(parts[0], st)
            b = eval_expr(parts[1], st)
            if a.kind == "num" and b.kind == "num":
                try:
                    x, y = a.data, b.data
                    if op == "+":
                        return V("num", x + y)
                    if op == "-":
                        return V("num", x - y)
                    if op == "*":
                        return V("num", x * y)
                    if op == "/":
                        return V("num", x / y if y != 0 else float("nan"))
                    if op == "%":
                        return V("num", x % y if y != 0 else float("nan"))
                    if op == "^":
                        return V("num", x ** y)
                except (OverflowError, ValueError):
                    return UNK
            return UNK
    m = re.fullmatch(r"not(?![\w])\s*(.*)", s, re.S)
    if m:
        a = eval_expr(m.group(1), st)
        t = truthy(a)
        return V("bool", not t) if t is not None else UNK
    m = re.fullmatch(r"-\s*(.*)", s, re.S)
    if m and m.group(1).strip() != "":
        a = eval_expr(m.group(1), st)
        if a.kind == "num":
            return V("num", -a.data)
        return UNK
    m = re.fullmatch(r"#\s*(.*)", s, re.S)
    if m:
        a = eval_expr(m.group(1), st)
        if a.kind == "str":
            return V("num", float(len(a.data.encode("latin-1"))))
        if a.kind == "table":
            d = st.tables.get(a.data, {})
            ks = [k for k in d if k[0] == "n"]
            if ks and all(isinstance(k[1], int) for k in ks):
                return V("num", float(max([k[1] for k in ks] + [0])))
        return UNK
    if s == "({})" or s == "{}":
        return st.new_table()
    m = re.fullmatch(r"\(\{\.\.\.\}\)|\{\.\.\.\}", s)
    if m:
        return V("unknown", "varargs-pack")
    if re.fullmatch(r"\{.*\}", s, re.S):
        return V("unknown", "ctor")

    if "(" in s and s.endswith(")"):
        return UNK
    return V("unknown", "expr:" + s[:40])

def index_val(base, key, st):
    if base.kind == "global" and key.kind == "str":
        return V("index", (base, key))
    if base.kind == "jenv":
        kk = num_or_str_key(key)
        if kk is not None:
            return upenv_val(st, "%s.%s" % (base.data, kk))
        return V("unknown", "updyn")
    if base.kind == "table" and val_key(key) in st.tables.get(base.data, {}):
        return st.tables[base.data][val_key(key)]
    if base.kind == "table":
        return UNK
    if base.kind == "regs" and key.kind == "num" and float(key.data).is_integer():
        r = int(key.data)
        if r in st.assigned_r:
            return st.regs.get(r, V("nil"))
        return V("nil")
    if base.kind == "upval":
        return V("unknown", "upval-read")
    return V("index", (base, key)) if base.kind != "unknown" else UNK

def truthy(v):
    if v.kind == "nil":
        return False
    if v.kind == "bool":
        return v.data
    if is_const(v) or v.kind in ("global", "table", "tablelit", "closure", "regs"):
        return True
    return None

def cmp_vals(a, op, b):
    if a.kind == "unknown" or b.kind == "unknown":

        return None
    if op in ("==", "~="):
        if a.kind != b.kind:
            eq = False
        elif a.kind == "num":
            eq = a.data == b.data
        else:
            eq = a.data == b.data
        return eq if op == "==" else not eq
    if a.kind == "num" and b.kind == "num":
        x, y = a.data, b.data
        return {"<": x < y, ">": x > y, "<=": x <= y, ">=": x >= y}[op]
    if a.kind == "str" and b.kind == "str" and op in ("<", ">", "<=", ">="):
        x, y = a.data, b.data
        return {"<": x < y, ">": x > y, "<=": x <= y, ">=": x >= y}[op]
    return None

def render_val(v, st):
    if v.kind == "num":
        f = v.data
        if float(f).is_integer() and abs(f) < 2 ** 53:
            return str(int(f))
        return repr(f)
    if v.kind == "str":
        return lua_quote(v.data)
    if v.kind == "bool":
        return "true" if v.data else "false"
    if v.kind == "nil":
        return "nil"
    if v.kind == "global":
        return v.data
    if v.kind == "upval":
        return "up_%s" % re.sub(r"[^\w]", "_", str(v.data))
    if v.kind == "closure":
        return "chain_%d" % v.data
    if v.kind == "reg":
        return "r[%d]" % v.data
    if v.kind == "param":
        return "p%d" % v.data
    if v.kind == "jenv":
        return "nil"
    if v.kind == "tablelit":
        return render_tablelit(v.data, st)
    if v.kind == "table":
        return render_tablelit(st.tables.get(v.data, {}), st)
    if v.kind == "index":
        base, key = v.data
        b, k = render_val(base, st), render_val(key, st)
        if b == "nil":
            b = "(nil)"
        if re.fullmatch(r"[A-Za-z_]\w*", k.strip('"')) and key.kind == "str":
            return "%s.%s" % (b, key.data)
        return "%s[%s]" % (b, k)
    if v.kind == "regs":
        return "d"
    return "nil"

def render_tablelit(d, st):
    if not d:
        return "{}"
    arr, hash_ = [], []
    for k, v in sorted(d.items(), key=lambda kv: str(kv[0])):
        if k[0] == "n" and isinstance(k[1], int) and k[1] >= 1:
            arr.append((k[1], v))
        else:
            if k[0] == "str":
                kk = k[1] if re.fullmatch(r"[A-Za-z_]\w*", k[1]) else "[%s]" % lua_quote(k[1])
            elif k[0] == "n":
                kk = "[%s]" % render_val(V("num", k[1]), st)
            else:
                kk = "[%s]" % k[1]
            hash_.append("%s = %s" % (kk, render_val(v, st)))
    arr.sort()
    seq = [render_val(v, st) for _, v in arr]
    return "{ %s }" % ", ".join(seq + hash_)

def uses_unknown(vals, st):
    """Flag approx when an unknown value flows into emitted output."""
    for v in vals:
        if isinstance(v, V) and v.kind == "unknown":
            st.approx = True
            return True
    return False

def render_call(func, args, st):

    if func.kind == "index" and args:
        base, key = func.data
        if key.kind == "str" and args[0] == base:
            b = render_val(base, st)
            if b == "nil":
                b = "(nil)"
            return "%s:%s(%s)" % (b, key.data,
                                  ", ".join(render_val(a, st) for a in args[1:]))
    f = render_val(func, st)
    if f == "nil":

        f = "(nil)"
    return "%s(%s)" % (f, ", ".join(render_val(a, st) for a in args))

CALL_PATTERNS = [

    re.compile(r"^\(d\[([^\]]+)\]\)\((.*)\)$"),
    re.compile(r"^d\[([^\]]+)\]\(d\[([^\]]+)\]\)\((.*)\)$"),
]

PC_REGS = ("G", "F", "E")
JUMP_RE = re.compile(r"^(?:%s)\s*=\s*\(?\s*(\d+)\s*\)?\s*;?\s*$" % "|".join(PC_REGS))

INC_RE = re.compile(r"^[A-Za-z_]\w*\s*\+=\s*[\d.]+\s*;?$")

def classify_slot(lines, raw):
    """Return a plan for one slot's cleaned+substituted lines."""

    lines = [ln for ln in lines if not INC_RE.match(ln.strip())]
    if not lines:
        return ("nop", None)
    if len(lines) == 1:
        m = JUMP_RE.match(lines[0].strip())
        if m:
            return ("jump", int(m.group(1)))
        m = re.match(r"^return\s*(.*)$", lines[0].strip())
        if m:
            return ("return", m.group(1).strip())

    if lines and lines[0].strip().startswith("if ") and lines[0].strip().endswith("then"):
        jumps = [(i, ln) for i, ln in enumerate(lines) if JUMP_RE.match(ln.strip())]
        other_ctrl = any(
            re.match(r"^(for\b|while\b|repeat\b|function\b|return\b)", ln.strip())
            for ln in lines[1:])
        if len(jumps) == 1 and not other_ctrl:
            ji, jln = jumps[0]
            m = JUMP_RE.match(jln.strip())
            cond = lines[0].strip()[3:-4].strip()
            else_at = next((i for i, ln in enumerate(lines)
                            if re.match(r"^else\b", ln.strip())), None)
            pol = "then" if (else_at is None or ji < else_at) else "else"
            return ("cjump", (cond, int(m.group(1)), pol))

        retidx = [i for i, ln in enumerate(lines[1:], 1) if re.match(r"^return\b", ln.strip())]
        loops = any(re.match(r"^(for\b|while\b|repeat\b|function\b)", ln.strip())
                    for ln in lines[1:])
        if len(retidx) == 1 and not loops and not jumps:
            cond = lines[0].strip()[3:-4].strip()
            else_at = next((i for i, ln in enumerate(lines)
                            if re.match(r"^else\b", ln.strip())), None)
            pol = "then" if (else_at is None or retidx[0] < else_at) else "else"
            return ("condret", (cond, pol, lines[retidx[0]].strip()))

    for ln in lines:
        s = ln.strip()
        if re.match(r"^(if\b|for\b|while\b|repeat\b|else|elseif\b|end|until\b|do\b|function\b)", s):
            return ("complex", None)
    return ("seq", None)

def parse_call_args(argtext, st):
    """Expand d[K+1], A[25](K+1,T,d) style arg lists to value lists."""
    argtext = argtext.strip()
    if not argtext:
        return []
    m = re.fullmatch(r"A\[25\]\(K\+1\.0,T,d\)|A\[25\]\(K\+1,T,d\)", argtext)
    if m:
        k = st.temps.get("K")
        t = st.temps.get("T")
        if k is not None and isinstance(k, V) and k.kind == "num" and \
                t is not None and isinstance(t, V) and t.kind == "num":
            ki, ti = int(k.data), int(t.data)
            if 0 <= ti - ki <= 64:
                return [(st.regs[r] if r in st.assigned_r else V("nil"))
                        for r in range(ki + 1, ti + 1)]
        return [V("unknown", "multret")]
    parts = split_top(argtext, ",")
    vals = []
    for p in parts:
        p = p.strip()
        if not p:
            continue
        vals.append(eval_expr(p, st))
    return vals

def exec_call_stmt(s, st, out):
    """Handle one call-shaped statement; True if consumed."""

    m = re.fullmatch(r"\(d\[([^\]]+)\]\)\(\)", s)
    if m:
        tgt = resolve_call_target(eval_expr("d[%s]" % m.group(1), st), st)
        uses_unknown([tgt], st)
        out.append("%s()" % render_val(tgt, st))
        return True

    m = re.fullmatch(r"(?:\(d\)\[([^\]]+)\]|d\[([^\]]+)\])\s*=\s*(.*)", s)
    if m and "(" in (m.group(3) or ""):
        lhs = m.group(1) or m.group(2)
        rhs = m.group(3).strip()
        cm = re.fullmatch(r"(?:\(d\[([^\]]+)\]\)|d\[([^\]]+)\])\((.*)\)", rhs)
        if cm:
            kexpr = cm.group(1) or cm.group(2)
            func = resolve_call_target(eval_expr("d[%s]" % kexpr, st), st)
            args = [st.snapshot(a) for a in parse_call_args(cm.group(3), st)]
            uses_unknown([func] + args, st)
            ass = eval_expr(lhs, st)
            call = render_call(func, args, st)
            if ass.kind == "num" and float(ass.data).is_integer():
                out.append("r[%d] = %s" % (int(ass.data), call))
                st.regs[int(ass.data)] = V("unknown", "callres")
                st.assigned_r.add(int(ass.data))
            else:
                out.append(call)
            return True

    m = re.fullmatch(r"\(d\[([^\]]+)\]\)\((.*)\)", s)
    if m:
        func = resolve_call_target(eval_expr("d[%s]" % m.group(1), st), st)
        args = [st.snapshot(a) for a in parse_call_args(m.group(2), st)]
        uses_unknown([func] + args, st)
        out.append(render_call(func, args, st))
        return True

    m = re.fullmatch(r"d\[([^\]]+)\]\((.*)\)", s)
    if m:
        func = resolve_call_target(eval_expr("d[%s]" % m.group(1), st), st)
        args = [st.snapshot(a) for a in parse_call_args(m.group(2), st)]
        uses_unknown([func] + args, st)
        out.append(render_call(func, args, st))
        return True

    m = re.fullmatch(r"K\((.*)\)", s)
    if m and isinstance(st.temps.get("K"), V) and st.temps["K"].kind == "regs":
        args = parse_call_args(m.group(1), st)
        if args:
            func = resolve_call_target(args[0], st)
            rest = [st.snapshot(a) for a in args[1:]]
            uses_unknown([func] + rest, st)
            out.append(render_call(func, rest, st))
            return True
    return False

def resolve_call_target(func, st):
    if func.kind == "reg":
        return st.regs.get(func.data, func)
    return func

FOR_HEAD = re.compile(
    r"^for\s+([A-Za-z_]\w*)\s*=\s*(.+?)\s*,\s*(.+?)(?:\s*,\s*(.+?))?\s*do\s*(.*)$")

def exec_range_loop(sub, st, out):
    """Model register range-fill slots (clear/copy idioms). True = handled.

    Shapes (post-substitution): op111/op39 clear K..q via regs-alias n;
    op152 clear w..D via d[H]=(nil); op29 copy into d[p] from vararg area L.
    Anything else with a loop header returns None (caller treats as complex).
    """
    heads = [(i, ln) for i, ln in enumerate(sub) if re.match(r"^for\b", ln.strip())]
    if len(heads) != 1:
        return None
    hi, hln = heads[0]
    m = FOR_HEAD.match(hln.strip())
    if not m:
        return None
    var, lo_s, hi_s = m.group(1), m.group(2), m.group(3)

    for ln in sub[:hi]:
        if exec_micro(ln, st, out) == "bail":
            return None
    rest = m.group(5).strip()
    after = sub[hi + 1:]

    close_at = next((k for k, ln in enumerate(after)
                     if ln.strip() in ("end", "until false")), None)
    if close_at is None:
        return None
    body = ([rest] if rest else []) + [ln.strip() for ln in after[:close_at]]
    post = [ln for ln in after[close_at + 1:] if ln.strip() not in ("end", "until false")]
    if any(re.match(r"^(if\b|for\b|while\b|repeat\b|function\b|return\b|else\b|elseif\b|until\b|end\b|do\b)", ln)
           for ln in body):
        return None
    lo, hi_v = eval_expr(lo_s, st), eval_expr(hi_s, st)
    if lo.kind != "num" or hi_v.kind != "num":
        return None
    a, b = int(lo.data), int(hi_v.data)
    if not (0 <= a <= 8000 and 0 <= b <= 8000 and 0 <= b - a <= 3000):
        return None

    is_clear = bool(body) and all(
        re.fullmatch(r"n\s*=\s*\(d\)", ln)
        or re.fullmatch(r"g\s*=\s*\(?" + re.escape(var) + r"\)?", ln)
        or re.fullmatch(r"(M|p)\s*=\s*nil", ln)
        or re.fullmatch(r"\(n\)\[g\]\s*=\s*\((M|p)\)", ln)
        or re.fullmatch(r"(?:\(d\)\[.+?\]|d\[.+?\])\s*=\s*\(nil\)", ln)
        for ln in body)

    writes_reg = any(re.match(r"^(?:\(d\)\[|d\[|\(n\)\[g\])", ln) for ln in body)
    if is_clear:
        for r in range(a, b + 1):
            st.regs[r] = V("nil")
            st.assigned_r.add(r)
    elif writes_reg:
        for r in range(a, b + 1):
            st.regs[r] = V("unknown", "rangefill")
            st.assigned_r.add(r)
    else:
        return None
    for ln in post:
        if exec_micro(ln, st, out) == "bail":
            return None
    return True

TEMP_ALT = (r"K|q|n|g|T|b|v|e|h|o|a|S|L|U|W|E|X|N|r|u|M|P"
            r"|v[A-Za-z]+|t")
TEMP_SET = set("K q n g T b v e h o a S L U W E X N r u M P t".split()) | {
    "vg", "ve", "vu", "vH", "vq", "vE", "vb"}

def temp_index(s, st):
    """Resolve an index expression through temp aliases.

    `eval_expr` does not resolve temp names (they stay `unknown name:X`), so
    `d[vg+1.0]` and `vg[ve]=vu` need this: a bare num temp, or a num temp plus
    a numeric offset. Returns int or None.
    """
    s = s.strip()
    m = re.fullmatch(r"([A-Za-z_]\w*)\s*\+\s*([\d.]+)", s)
    if m:
        b = st.temps.get(m.group(1))
        if isinstance(b, V) and b.kind == "num":
            try:
                return int(b.data + float(m.group(2)))
            except (OverflowError, ValueError):
                return None
        return None
    if re.fullmatch(r"[A-Za-z_]\w*", s):
        b = st.temps.get(s)
        if isinstance(b, V) and b.kind == "num" and float(b.data).is_integer():
            return int(b.data)
    return None

def exec_micro(s, st, out):
    """Execute one cleaned statement. Returns 'ok' | 'skip' | 'bail'."""
    s = s.strip().rstrip(";").strip()
    if not s or s.startswith("--"):
        return "skip"

    if re.fullmatch(r"[A-Za-z_]\w*\+=1\.0", s):
        return "skip"

    m = re.fullmatch(r"while\s+(.+?)\s+do\s+return\s*(.*?)\s*;\s*end", s)
    if m:
        cv = eval_expr(m.group(1), st)
        t = truthy(cv)
        if t is None:

            st.approx = True
            return "skip"
        if bool(t):
            out.append("return %s" % (m.group(2).strip() or ""))
            return "ok-return"
        return "skip"
    if re.match(r"^(local\b|for\b|while\b|repeat\b|else|elseif\b|end|until\b|do\b|function\b|break$)", s):

        if s in ("end", "else", "do"):
            return "skip"
        return "bail"
    if exec_call_stmt(s, st, out):
        return "ok"

    m = re.fullmatch(r"(?:\(d\)\[([^\]]+)\]|d\[([^\]]+)\]|\(d\[([^\]]+)\]\))\s*=\s*(.*)", s, re.S)
    if m:
        lhs = m.group(1) or m.group(2) or m.group(3)
        rhs = m.group(4)
        idx = eval_expr(lhs, st)
        if idx.kind == "num" and float(idx.data).is_integer():
            v = eval_expr(rhs, st)
            if rhs.strip().startswith("A[25](") or rhs.strip().startswith("A[48]("):
                v = V("unknown", "multret")
            st.regs[int(idx.data)] = v
            st.assigned_r.add(int(idx.data))
            return "ok"

        rr = temp_index(lhs, st)
        if rr is not None:
            st.regs[rr] = eval_expr(rhs, st)
            st.assigned_r.add(rr)
            return "ok"
        return "bail"

    m = re.fullmatch(r"\(d\[([^\]]+)\]\)\[([^\]]+)\]\s*=\s*(.*)", s, re.S)
    if m:
        base = eval_expr("d[%s]" % m.group(1), st)
        key = eval_expr(m.group(2), st)
        val = st.snapshot(eval_expr(m.group(3), st))
        if base.kind == "table":
            kk = val_key(key)
            if kk is not None:
                st.tables[base.data][kk] = val
                return "ok"
            return "skip"
        if base.kind == "unknown":
            return "skip"

        st.approx = True
        return "skip"

    m = re.fullmatch(r"(" + TEMP_ALT + r")\s*=\s*(.*)", s, re.S)
    if m:
        name, rhs = m.group(1), m.group(2).strip()
        if rhs.startswith("A[25](") or rhs.startswith("A[48](") or rhs == "a()":
            st.temps[name] = V("unknown", "helper")
            st.assigned_t.add(name)
            return "ok"
        v = eval_expr(rhs, st)
        if name == "K" and v.kind == "regs":
            st.temps[name] = v
            st.assigned_t.add(name)
            return "ok"
        if name == "K" and isinstance(v, V) and v.kind == "table":
            st.temps[name] = v
            st.assigned_t.add(name)
            return "ok"
        st.temps[name] = v
        st.assigned_t.add(name)
        return "ok"
    m = re.fullmatch(r"\(K\)\[([^\]]+)\]\s*=\s*(.*)", s, re.S)
    if m:
        key = eval_expr(m.group(1), st)
        val = st.snapshot(eval_expr(m.group(2), st))
        k = st.temps.get("K")
        if k is not None and isinstance(k, V) and k.kind == "regs" and \
                key.kind == "num" and float(key.data).is_integer():
            st.regs[int(key.data)] = val
            st.assigned_r.add(int(key.data))
            return "ok"
        if k is not None and isinstance(k, V) and k.kind == "table":
            kk = val_key(key)
            if kk is not None:
                st.tables[k.data][kk] = val
                return "ok"
        return "skip"

    m = re.fullmatch(r"K\[([^\]]+)\]\s*=\s*(.*)", s, re.S)
    if m:
        key = eval_expr(m.group(1), st)
        val = st.snapshot(eval_expr(m.group(2), st))
        k = st.temps.get("K")
        if k is not None and isinstance(k, V) and k.kind == "regs" and \
                key.kind == "num" and float(key.data).is_integer():
            st.regs[int(key.data)] = val
            st.assigned_r.add(int(key.data))
            return "ok"
        if k is not None and isinstance(k, V) and k.kind == "table":
            kk = val_key(key)
            if kk is not None:
                st.tables[k.data][kk] = val
                return "ok"
        return "skip"

    m = re.fullmatch(r"\(?([A-Za-z_]\w*)\)?\[([^\]]+)\]\s*=\s*(.*)", s, re.S)
    if m:
        name, idxs, rhs = m.group(1), m.group(2), m.group(3)
        if name in ("d", "G", "F", "E", "r"):
            return "bail"
        if name in TEMP_SET or re.fullmatch(r"v[A-Za-z]+", name):
            tval = st.temps.get(name)
            val = st.snapshot(eval_expr(rhs, st))
            if isinstance(tval, V) and tval.kind == "table":
                kk = val_key(eval_expr(idxs, st))
                if kk is None:
                    kk = temp_index(idxs, st)
                if kk is not None:
                    st.tables[tval.data][kk] = val
                    return "ok"
                st.approx = True
                return "skip"
            if isinstance(tval, V) and tval.kind == "regs":
                rr = temp_index(idxs, st)
                if rr is None:
                    kk = eval_expr(idxs, st)
                    rr = int(kk.data) if kk.kind == "num" and float(kk.data).is_integer() else None
                if rr is not None:
                    st.regs[rr] = val
                    st.assigned_r.add(rr)
                    return "ok"
                st.approx = True
                return "skip"

            st.approx = True
            return "skip"
        return "bail"

    m = re.fullmatch(r"d\[([^\]]+)\]\[([^\]]+)\]\s*=\s*(.*)", s, re.S)
    if m:
        base = eval_expr("d[%s]" % m.group(1), st)
        key = eval_expr(m.group(2), st)
        val = st.snapshot(eval_expr(m.group(3), st))
        if base.kind == "table":
            kk = val_key(key)
            if kk is not None:
                st.tables[base.data][kk] = val
                return "ok"
            return "skip"
        if base.kind == "unknown":
            return "skip"

        st.approx = True
        return "skip"

    m = re.fullmatch(r"(" + TEMP_ALT + r")\s*([+\-*/%^])=\s*(.*)", s, re.S)
    if m:
        name, op, rhs = m.group(1), m.group(2), m.group(3)
        b = eval_expr(rhs, st)
        a = st.temps.get(name, V("nil")) if name in st.assigned_t else V("nil")
        if a.kind == "num" and b.kind == "num":
            x, y = a.data, b.data
            try:
                st.temps[name] = V("num", {"+": x + y, "-": x - y,
                                          "*": x * y, "/": x / y if y else float("nan"),
                                          "%": x % y if y else float("nan"),
                                          "^": x ** y}[op])
            except (OverflowError, ValueError):
                st.temps[name] = UNK
        else:
            st.temps[name] = UNK
        st.assigned_t.add(name)
        return "ok"

    m = re.fullmatch(r"([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)+)\s*=\s*(.*)", s, re.S)
    if m:
        names = [w.strip() for w in m.group(1).split(",")]
        if all(w in TEMP_SET or re.fullmatch(r"v[A-Za-z]+", w) for w in names):
            parts = split_top(m.group(2), ",")
            for w, pv in zip(names, parts):
                pvs = pv.strip()
                if pvs.startswith("A[25](") or pvs.startswith("A[48](") or pvs == "a()":
                    st.temps[w] = V("unknown", "helper")
                else:
                    st.temps[w] = eval_expr(pvs, st)
                st.assigned_t.add(w)
            for w in names[len(parts):]:
                st.temps[w] = V("nil")
                st.assigned_t.add(w)
            return "ok"
        return "bail"
    m = re.fullmatch(r"n\s*=\s*n\[g\]|n\s*=\s*n\[(.*)\]", s)
    if m:
        return "skip"
    m = re.fullmatch(r"n\s*([+\-*/%^]?)=\s*g", s)
    if m:
        op = m.group(1) or "="
        a = st.temps.get("n", UNK)
        b = st.temps.get("g", UNK)
        if a.kind == "num" and b.kind == "num":
            x, y = a.data, b.data
            try:
                st.temps["n"] = V("num", {"": y, "+": x + y, "-": x - y,
                                          "*": x * y, "/": x / y if y else float("nan"),
                                          "%": x % y if y else float("nan"),
                                          "^": x ** y}[op])
            except (OverflowError, ValueError):
                st.temps["n"] = UNK
        else:
            st.temps["n"] = UNK
        st.assigned_t.add("n")
        return "ok"

    if re.fullmatch(r"A\[4\]\[i\]\s*=.*|A\[24\]\s*=.*|\(A\)\[.*", s):
        return "skip"
    return "bail"

MAXFORK = 4

def chain_arity(cid, gs, slots, leaves):
    """Function arity from the varargs-init slot (op97 `K={...}; d[1..D]`)."""
    for g in gs:
        vals = slots[(cid, g)]
        try:
            P = int(float(vals["t"])) if re.fullmatch(r"-?\d+(?:\.\d+)?", vals["t"] or "") else -1
        except (ValueError, TypeError):
            continue
        raw = leaves.get(P)
        if raw and "{...}" in raw:
            d = vals.get("D", "-")
            if re.fullmatch(r"-?\d+(?:\.\d+)?", d or ""):
                return int(float(d))
    return 0

def slot_plan(cid, pc, slots, leaves):
    """Cleaned+substituted lines, classification, raw leaf and operands."""
    vals = slots[(cid, pc)]
    try:
        P = int(float(vals["t"])) if re.fullmatch(r"-?\d+(?:\.\d+)?", vals["t"] or "") else -1
    except (ValueError, TypeError):
        P = -1
    raw = leaves.get(P)
    if raw is None:
        return None, ("noleaf", None), P, vals
    core = clean_leaf(raw)
    cut = []
    for ln in core:
        cut.append(ln)
        if re.match(r"^\s*return\b", ln):
            break
    sub = []
    for ln in cut:
        s = substitute(ln, vals)
        s = re.sub(r";\s*;", ";", s).strip().lstrip(";").strip()
        if s:
            sub.append(s)
    return sub, classify_slot(sub, raw), P, vals

def simulate(cid, gs, slots, leaves, f2chain, upenv=None, cmap=None):
    gset = set(gs)
    idx_of = {g: i for i, g in enumerate(gs)}
    arity = chain_arity(cid, gs, slots, leaves)
    steps = [0]

    plans = {}
    for g in gs:
        plans[g] = slot_plan(cid, g, slots, leaves)

    def nxt_of(pc):
        i = idx_of[pc]
        return gs[i + 1] if i + 1 < len(gs) else None

    def succ(pc):

        sub, plan, P, vals = plans[pc]
        kind = plan[0]
        if kind == "jump":
            t = plan[1] + 1
            return (t,) if t in gset else ()
        if kind == "cjump":
            outs = []
            t = plan[1][1] + 1
            if t in gset:
                outs.append(t)
            n = nxt_of(pc)
            if n is not None:
                outs.append(n)
            return tuple(outs)
        if kind == "return":
            return ()
        n = nxt_of(pc)
        return (n,) if n is not None else ()

    def find_join(a, b):
        """Nearest common reachable slot from a and b (BFS); None if none."""
        if a is None or b is None:
            return None
        if a == b:
            return a
        seen_a, seen_b = {a}, {b}
        front_a, front_b = [a], [b]
        for _ in range(3000):
            nxt_a = []
            for pc in front_a:
                for q in succ(pc):
                    if q in seen_b:
                        return q
                    if q not in seen_a:
                        seen_a.add(q)
                        nxt_a.append(q)
            front_a = nxt_a
            nxt_b = []
            for pc in front_b:
                for q in succ(pc):
                    if q in seen_a:
                        return q
                    if q not in seen_b:
                        seen_b.add(q)
                        nxt_b.append(q)
            front_b = nxt_b
            if not front_a and not front_b:
                return None
        return None

    def run(pc, st, depth, entered, stop):
        """Returns (stmts, end, end_pc, end_state, note).

        end: end (returned/fell off/stopped at `stop`), loop, bail.
        `stop` bounds fork exploration at the statically found join.
        `entered` (shared, mutated) holds every pc executed for this chain;
        revisiting one is a loop.
        """
        out = []
        while pc is not None:
            if stop is not None and pc == stop:
                return out, "join", pc, st, ""
            if steps[0] >= STEP_LIMIT:
                return out, "bail", pc, st, "step budget exhausted"
            steps[0] += 1
            if pc in entered:
                return out, "loop", pc, st, "loop at slot %d" % pc
            entered.add(pc)
            sub, plan, P, vals = plans[pc]
            if plan[0] == "noleaf":
                return out, "bail", pc, st, "no leaf for opcode %s at slot %d" % (vals["t"], pc)
            kind = plan[0]
            data = plan[1]
            nxt = nxt_of(pc)
            if sub and any("{...}" in ln for ln in sub):

                d = vals.get("D", "-")
                if re.fullmatch(r"-?\d+(?:\.\d+)?", d or ""):
                    for r in range(1, int(float(d)) + 1):
                        st.regs[r] = V("param", r)
                        st.assigned_r.add(r)
                pc = nxt
                continue
            if kind == "jump":
                t = data + 1
                if t not in gset:
                    return out, "bail", pc, st, "jump to %d outside chain" % t
                pc = t
                continue
            if kind == "cjump":
                cond, tgt, pol = data
                tgt += 1
                cv = eval_expr(cond, st)
                t = truthy(cv)
                if t is not None:
                    taken = (bool(t) and pol == "then") or ((not bool(t)) and pol == "else")
                    if taken and tgt not in gset:
                        return out, "bail", pc, st, "branch to %d outside chain" % tgt
                    pc = tgt if taken else nxt
                    continue
                csrc = render_cond(cond, st)
                if csrc is None or depth >= MAXFORK:
                    return out, "bail", pc, st, "unknown condition at slot %d: %s" % (pc, comment_safe(cond)[:100])
                then_pc = (tgt + 1) if pol == "then" else nxt
                else_pc = nxt if pol == "then" else (tgt + 1)
                if then_pc is not None and then_pc not in gset:
                    return out, "bail", pc, st, "branch to %d outside chain" % then_pc
                if else_pc is not None and else_pc not in gset:
                    return out, "bail", pc, st, "branch to %d outside chain" % else_pc
                join = find_join(then_pc, else_pc)
                if join is None:

                    if (then_pc is None) != (else_pc is None):
                        ret_first = then_pc is None
                        outA, endA, pcA, stA, noteA = run(
                            else_pc if ret_first else then_pc,
                            st.copy(), depth + 1, entered, None)
                        if endA == "loop" or endA == "bail":
                            return out, endA, pcA, st, "branch from slot %d: %s" % (pc, noteA)
                        if endA == "end" and pcA is None:
                            out.append(("if", csrc,
                                        [] if ret_first else outA,
                                        outA if ret_first else []))
                            return out, "end", None, st if ret_first else stA, ""
                    return out, "bail", pc, st, "branches from slot %d do not rejoin" % pc
                outA, endA, pcA, stA, noteA = run(then_pc, st.copy(), depth + 1, entered, join)
                if endA == "loop" or endA == "bail":
                    return out, endA, pcA, st, "branch from slot %d: %s" % (pc, noteA)
                outB, endB, pcB, stB, noteB = run(else_pc, st.copy(), depth + 1, entered, join)
                if endB == "loop" or endB == "bail":
                    return out, endB, pcB, st, "branch from slot %d: %s" % (pc, noteB)
                if endA == "end" and pcA is None and endB == "join":

                    out.append(("if", csrc, outA, outB))
                    return out, "end", join, stB, ""
                if endB == "end" and pcB is None and endA == "join":
                    out.append(("if", csrc, outA, outB))
                    return out, "end", join, stA, ""
                if endA == "join" and endB == "join" and pcA == pcB == join:
                    out.append(("if", csrc, outA, outB))
                    return out, "end", join, merge_states(stA, stB), ""
                return out, "bail", pc, st, "branches from slot %d do not rejoin" % pc
            if kind == "condret":
                cond, pol, retline = data
                retv = st.snapshot(eval_expr(retline[6:].strip().rstrip(";").strip() or "nil", st))
                ret_unknown = retv.kind == "unknown"
                cv = eval_expr(cond, st)
                t = truthy(cv)

                if t is not None:
                    taken = bool(t)
                    returns = (taken and pol == "then") or ((not taken) and pol == "else")
                    if returns:
                        uses_unknown([retv], st)
                        out.append("return %s" % render_val(retv, st) if retv.kind != "nil" else "return")
                        return out, "end", None, st, ""
                    pc = nxt
                    continue
                csrc = render_cond(cond, st)
                if csrc is None or depth >= MAXFORK:
                    return out, "bail", pc, st, "unknown condition at slot %d: %s" % (pc, comment_safe(cond)[:100])

                then_pc = None if pol == "then" else nxt
                else_pc = None if pol == "else" else nxt
                if (then_pc is not None and then_pc not in gset) or \
                   (else_pc is not None and else_pc not in gset):
                    return out, "bail", pc, st, "branch outside chain at slot %d" % pc
                join = find_join(then_pc, else_pc)

                run_pc = else_pc if pol == "then" else then_pc
                outB, endB, pcB, stB, noteB = run(run_pc, st.copy(), depth + 1, entered, join)
                if endB == "loop" or endB == "bail":
                    return out, endB, pcB, st, "branch from slot %d: %s" % (pc, noteB)
                outA = ["return %s" % render_val(retv, st) if retv.kind != "nil" else "return"]
                if ret_unknown:
                    st.approx = True
                    stB.approx = True
                then_out, else_out = (outA, outB) if pol == "then" else (outB, outA)
                if join is None:
                    if endB == "end" and pcB is None:
                        out.append(("if", csrc, then_out, else_out))
                        return out, "end", None, st, ""
                    return out, "bail", pc, st, "branches from slot %d do not rejoin" % pc
                if endB == "join" and pcB == join:
                    out.append(("if", csrc, then_out, else_out))
                    return out, "end", join, stB, ""
                if endB == "end" and pcB is None:

                    out.append(("if", csrc, then_out, else_out))
                    return out, "end", None, st, ""
                return out, "bail", pc, st, "branches from slot %d do not rejoin" % pc
            if kind == "return":
                expr = (data or "").strip()
                if not expr or expr == ";":
                    out.append("return")
                else:
                    m = re.fullmatch(r"A\[25\]\(D,T,d\)", expr)
                    if m:
                        d = vals.get("D", "-")
                        t = st.temps.get("T")
                        if re.fullmatch(r"-?\d+(?:\.\d+)?", d or "") and \
                                t is not None and isinstance(t, V) and t.kind == "num":
                            lo, hi = int(float(d)), int(t.data)
                            if 0 <= hi - lo <= 64:
                                rets = [st.snapshot(st.regs[r] if r in st.assigned_r else V("nil"))
                                        for r in range(lo, hi + 1)]
                                uses_unknown(rets, st)
                                out.append("return %s" % ", ".join(render_val(v, st) for v in rets) if rets else "return")
                            else:
                                out.append("return --[[multret]]")
                        else:
                            out.append("return --[[multret]]")
                    else:
                        v = st.snapshot(eval_expr(expr, st))
                        uses_unknown([v], st)
                        out.append("return %s" % render_val(v, st))
                return out, "end", None, st, ""
            if kind == "nop":
                pc = nxt
                continue
            if kind == "complex":
                txt = "\n".join(sub)

                if any(re.match(r"^for\b", ln.strip()) for ln in sub):
                    handled = exec_range_loop(sub, st, out)
                    if handled:
                        pc = nxt
                        continue
                    if handled is None:
                        pass
                    else:
                        pc = nxt
                        continue
                if re.search(r"(^|\n)\s*return\b", txt):

                    st.approx = True
                txt = "\n".join(sub)

                last = sub[-1].strip() if sub else ""
                if re.fullmatch(r"return\s+A\[25\]\(D,T,d\)", last):
                    d = vals.get("D", "-")
                    t = st.temps.get("T")
                    if re.fullmatch(r"-?\d+(?:\.\d+)?", d or "") and \
                            t is not None and isinstance(t, V) and t.kind == "num":
                        lo, hi = int(float(d)), int(t.data)
                        if 0 <= hi - lo <= 64:
                            rets = [st.snapshot(st.regs[r] if r in st.assigned_r else V("nil"))
                                    for r in range(lo, hi + 1)]
                            out.append("return %s" % ", ".join(render_val(v, st) for v in rets) if rets else "return")
                        else:
                            out.append("return --[[multret]]")
                    else:
                        out.append("return --[[multret]]")
                    return out, "end", None, st, ""
                mt = re.fullmatch(r"return\s+(d\[.+\]\(.*\))", last)
                if mt:
                    func_m = re.fullmatch(r"d\[([^\]]+)\]\((.*)\)", mt.group(1))
                    if func_m:
                        func = eval_expr("d[%s]" % func_m.group(1), st)
                        args = parse_call_args(func_m.group(2), st)
                        out.append("return %s" % render_call(resolve_call_target(func, st),
                                                             [st.snapshot(a) for a in args], st))
                        return out, "end", None, st, ""
                if re.match(r"^return\b", last):
                    if any(re.match(r"^(if\b|for\b|while\b|repeat\b|elseif\b)", ln.strip()) for ln in sub[:-1]):
                        st.approx = True
                    out.append("return")
                    return out, "end", None, st, ""
                if re.search(r"(^|\n)\s*return\b", txt):
                    st.approx = True
                for m in re.finditer(r"\(d\)\[(\d+)\]|d\[(\d+)\]", txt):
                    r = int(m.group(1) or m.group(2))
                    st.regs[r] = V("unknown", "complex:P%d" % P)
                    st.assigned_r.add(r)
                if P in (188, 189) or "A[49](K,g)" in txt:
                    iop = vals.get("i", "-")
                    if re.fullmatch(r"-?\d+(?:\.\d+)?", iop or ""):
                        fop = (vals.get("f") or "")
                        target = f2chain.get(fop[7:]) if fop.startswith("table: ") else None
                        st.regs[int(float(iop))] = V("closure", target) if target is not None \
                            else V("unknown", "closure")
                        st.assigned_r.add(int(float(iop)))
                pc = nxt
                continue

            failed = None
            returned = False
            for ln in sub:
                r = exec_micro(ln, st, out)
                if r == "bail":
                    failed = ln
                    break
                if r == "ok-return":
                    returned = True
                    break
            if failed is not None:
                return out, "bail", pc, st, "unmodelled statement at slot %d: %s" % (pc, comment_safe(failed)[:120])
            if returned:
                return out, "end", None, st, ""
            pc = nxt
        return out, "end", None, st, ""

    st0 = State()
    st0.chain = cid
    st0.upenv = (upenv or {}).get(str(cid), {})
    st0.cmap = cmap or {}
    if arity:
        for r in range(1, arity + 1):
            st0.regs[r] = V("param", r)
            st0.assigned_r.add(r)
    out, end, _, end_state, note = run(gs[0] if gs else None, st0, 0, set(), None)
    status = "complete" if end == "end" else "partial"
    if status == "complete" and end_state is not None and end_state.approx:
        status = "approx"
        note = "stepped over conditional VM returns"
    return out, status, note, arity

def flat_lines(tree, indent):
    """Flatten statement tree (strings + ('if', cond, then, else) nodes)."""
    out = []
    for node in tree:
        if isinstance(node, tuple) and node and node[0] == "if":
            _, cond, then_b, else_b = node
            out.append(indent + "if %s then" % cond)
            out.extend(flat_lines(then_b, indent + "    "))
            out.append(indent + "else")
            out.extend(flat_lines(else_b, indent + "    "))
            out.append(indent + "end")
        else:
            s = node.strip()
            if not s.startswith("--") and not re.match(
                    r"^(if\b.*\bthen|elseif\b.*\bthen|else|end|do|repeat|until\b|"
                    r"for\b|while\b|function\b|local\s+function\b|"
                    r"return\b|break)\s*.*$", s) and not s.endswith(";"):

                s += ";"
            out.append(indent + s)
    return out

def needs_decls(lines):
    regs = set(int(m.group(1)) for m in re.finditer(r"r\[(\d+)\]", "\n".join(lines)))
    ups = sorted(set(m.group(1) for m in re.finditer(r"\bup_([A-Za-z0-9_]+)", "\n".join(lines))))
    return regs, ups

def main() -> int:
    work = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else \
        pathlib.Path(__file__).resolve().parent / "work"
    dest = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else work / "simple.lua"
    lift14.PROFILE.update(lift14.detect_profile(work))
    print("profile=%s" % lift14.PROFILE.get("name"))
    slots, order = load_slots(work)
    leaves = load_leaves(work)
    f2c = {}
    f2p = work / "f2chain.json"
    if f2p.exists():
        try:
            f2c = json.loads(f2p.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            pass
    upenv = {}
    upp = work / "upenv.json"
    if upp.exists():
        try:
            upenv = json.loads(upp.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            pass
    cmap = {}
    cmp_ = work / "cmap.json"
    if cmp_.exists():
        try:
            cmap = json.loads(cmp_.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            pass
    if not slots:
        print("no chains in %s" % (work / "chains.tsv"), file=sys.stderr)
        return 2
    total = sum(len(v) for v in order.values())
    print("chains=%d slots=%d leaves=%d" % (len(order), total, len(leaves)))
    parts = ["-- Deobfuscated by OmniDBF (Luraph v14.7 simplifier v1)",
             "-- Detected obfuscation: Luraph v14.7",
             "-- program: %d functions (chains), %d instructions" % (len(order), total),
             "-- each chain below is the simulated user code; [[partial]] marks",
             "-- where simulation stopped (see lifted.lua for full dispatch form).",
             ""]
    stats = {"complete": 0, "partial": 0, "approx": 0, "stmts": 0}
    for cid in sorted(order):
        out, status, note, arity = simulate(cid, order[cid], slots, leaves, f2c, upenv, cmap)
        lines = flat_lines(out, "    ")
        regs, ups = needs_decls(lines)
        if status == "complete" and (regs or ups):
            status = "approx"
        stats[status] += 1
        stats["stmts"] += len(lines)
        if arity:
            parts.append("local function chain_%d(%s)" % (cid, ", ".join("p%d" % i for i in range(1, arity + 1))))
        else:
            parts.append("local function chain_%d(...)" % cid)
        parts.append("    -- %d slots, simulation: %s%s" %
                     (len(order[cid]), status, (" (" + note + ")") if note else ""))
        if regs:
            parts.append("    local r = {}")
        if ups:
            parts.append("    local %s --[[unresolved upvalues]]" % ", ".join("up_%s" % u for u in ups))
        if not lines:
            parts.append("    -- (no user-visible effects recovered)")
        parts.extend(lines)
        if status == "partial":
            parts.append("    -- [[partial: %s]]" % comment_safe(note)[:160])
        elif status == "approx":
            parts.append("    -- [[approx: some values unresolved (r[]/up_ above)]]")
        parts.append("end")
        parts.append("")
    dest.write_text("\n".join(parts), encoding="utf-8")
    print("wrote %s (%d chains complete, %d approx, %d partial, %d statements)" %
          (dest, stats["complete"], stats["approx"], stats["partial"], stats["stmts"]))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
