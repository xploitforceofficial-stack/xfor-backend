"""Lift Luraph v14 chains + opcode leaves into readable Luau (v15 style, v1).

Reads:
  tools/work/chains.tsv   one row per (chain, slot): c, g, t,i,w,D,f,O,z
  tools/work/opcodes/*.lua  leaf code A[49] runs for each opcode P

Writes:
  tools/work/lifted.lua   one `local function chain_N(...)` per chain,
                          goto-structured, operands substituted, VM junk
                          stripped, v15-style header.

This is v1: control flow is explicit (labels + goto, like the VM's G),
but every slot shows its real effect with concrete operands, which is
what the 69KB single-line stage hides. Full structuring (if/while,
real locals via backend.py) is the documented next step, not claimed here.

Usage: python tools/lift14.py [workdir] [out.lua]
"""
import pathlib
import re
import sys

FIELDS = ("t", "i", "w", "D", "f", "O", "z")

S2_RENAME = {
    "F": "G",
    "r": "d",
    "m": "t", "N": "i", "h": "w", "y": "D", "f": "f", "d": "O", "n": "z",

    "g": "vg", "e": "ve", "_": "vu", "q": "vq", "E": "vE", "b": "vb",
    "H": "vH", "a": "va", "k": "vk", "s": "vs", "J": "vJ", "I": "vI",
}
S2_RE = re.compile(r"\b[A-Za-z_]\w*\b")
IDENT_RE = re.compile(r"\b[A-Za-z_]\w*\b")

PROFILE = {"name": "canonical"}

def detect_profile(work: pathlib.Path) -> dict:
    """Pick a schema profile from markers the dumper leaves in the workdir.

    op.tsv carries a third column (loop tag) only for the multi-loop (2)
    family; the canonical (4) build writes pc/opcode only. An explicit
    `profile.json` always wins.
    """
    pj = work / "profile.json"
    if pj.exists():
        import json
        try:
            data = json.loads(pj.read_text(encoding="utf-8"))
            name = data.get("name", "canonical")
            return {"name": name, "rename": data.get("rename", {})}
        except Exception:
            pass
    op = work / "op.tsv"
    if op.exists():
        for line in op.read_text(encoding="utf-8").splitlines():
            if len(line.split("\t")) >= 3:
                return {"name": "s2", "rename": S2_RENAME}
            if line.strip():
                break
    return {"name": "canonical", "rename": {}}

def apply_profile(text: str) -> str:
    rmap = PROFILE.get("rename") or {}
    if not rmap:
        return text
    return IDENT_RE.sub(lambda m: rmap.get(m.group(0), m.group(0)), text)

def lua_quote(s: str) -> str:
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == '\\':
            out.append('\\\\')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        elif 32 <= o < 127:
            out.append(ch)
        else:
            out.append('\\%03d' % o)
    out.append('"')
    return ''.join(out)

def comment_safe(s: str) -> str:
    """Make any string safe for a `--` line comment: no control/raw bytes."""
    out = []
    for ch in s:
        o = ord(ch)
        if ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append(' ')
        elif 32 <= o < 127:
            out.append(ch)
        else:
            out.append('\\%03d' % o)
    return ''.join(out)

def fmt_val(v: str) -> str:
    if v is None or v == '-' or v == '':
        return 'nil'
    if re.fullmatch(r'-?\d+(?:\.\d+)?', v):

        try:
            f = float(v)
            if f.is_integer() and abs(f) < 2 ** 31:
                return str(int(f))
        except Exception:
            pass
        return v
    if v.startswith('table:'):
        return 'nil -- (%s)' % v
    return lua_quote(v)

def work_chains_path(work: pathlib.Path) -> pathlib.Path:
    """Prefer post-patch arrays (see join_chains.py); fall back to creation-time."""
    post = pathlib.Path(work) / "chains_post.tsv"
    if post.exists():
        return post
    return pathlib.Path(work) / "chains.tsv"

def load_slots(work: pathlib.Path):
    slots = {}
    order = {}
    raw = work_chains_path(work).read_bytes().decode('latin-1')
    for line in raw.splitlines():
        parts = line.split('\t')
        if len(parts) != 9:
            continue
        try:
            c, g = int(parts[0]), int(parts[1])
        except ValueError:
            continue
        vals = {}
        for k, p in enumerate(FIELDS):
            vals[p] = parts[2 + k].replace('\\t', '\t').replace('\\n', '\n')
        slots[(c, g)] = vals
        order.setdefault(c, []).append(g)
    for c in order:
        order[c] = sorted(set(order[c]))
    return slots, order

def load_leaves(work: pathlib.Path):
    leaves = {}
    d = work / 'opcodes'
    if not d.exists():
        return leaves
    for f in d.glob('*.lua'):
        try:
            P = int(f.stem)
        except ValueError:
            continue
        leaves[P] = apply_profile(f.read_text(encoding='utf-8', errors='replace'))
    return leaves

JUNK_LINE = re.compile(
    r'^\s*(local\s+p\s*=\s*\(\s*\d+\s*\)\s*;?'
    r'|local\s+M\s*=\s*75\s*;?'
    r'|N\s*,\s*r\s*=\s*M\b.*'
    r'|A\s*\[\s*\d+\s*\]\s*,\s*A\s*\[.*'
    r'|\(A\)\s*\[.*'
    r'|while\s*-?\d*\s*or\s*A\[.*do\s*return\b.*'
    r'|while\s+\w+\s+do\s*return\b.*'
    r'|while\s+true\s+do\s*return\b.*'
    r'|while\s*-?\d+\s*<=\s*J\s*do\s*return\b.*'
    r'|while\s*-?\d+\s*<=\s*J\s*do\s*return\s*;?\s*end\s*;?'
    r'|while\s+M\s+do\s*return\b.*'
    r'|while\s+A\[.*do\s*return\b.*'
    r'|repeat\s*\(A\)\[.*'
    r'|if\s+not\s*\(\s*-A\[31\]\s*\)\s*then\s*$'
    r'|if\s+A\[.*then\s*$'
    r'|if\s+not\s*\(\s*I\s*\)\s*then\s*$'
    r'|return\s+M\s*;?\s*$'
    r'|return\s+\d+\s*;?\s*$'
    r'|return\s+J\s*;?\s*$'
    r'|return\s+A\[.*$'
    r')\s*$'
)

CLOSER_RE = re.compile(r'^(end|until\b)')
ELSE_RE = re.compile(r'^else\b')

def strip_comments(text: str) -> list:
    lines = []
    for ln in text.splitlines():
        s = ln.strip()
        if not s or s.startswith('--'):
            continue
        lines.append(ln.rstrip())
    return lines

def split_statements(line: str) -> list:
    """Split a `;`-separated line into statements, respecting quotes."""
    parts, buf, q = [], [], None
    i = 0
    while i < len(line):
        ch = line[i]
        if q:
            buf.append(ch)
            if ch == '\\' and i + 1 < len(line):
                buf.append(line[i + 1])
                i += 2
                continue
            if ch == q:
                q = None
            i += 1
            continue
        if ch in ('"', "'"):
            q = ch
            buf.append(ch)
            i += 1
            continue
        if ch == ';':
            parts.append(''.join(buf))
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    parts.append(''.join(buf))
    return parts

JUNK_STMT = re.compile(
    r'^(local\s+M\s*=\s*75'
    r'|N\s*,\s*r\s*=\s*M\b'
    r'|A\s*\[\s*\d+\s*\]\s*,'
    r'|\(A\)\s*\[|\(A\)\s*,'
    r'|^A\s*\[\s*\d+\s*\]'
    r'|[A-ZJ]\s*,\s*[A-ZJ]\s*=\s*A\s*\['
    r')'
)

def clean_leaf(raw: str) -> list:
    """Drop header comments + pure-VM-junk statements, keep the real effect."""
    lines = strip_comments(raw)

    stmts = []
    for ln in lines:
        for part in split_statements(ln):
            s = part.strip()
            if s:
                stmts.append(s)
    kept = []
    for s in stmts:
        if JUNK_LINE.match(s):
            continue
        if JUNK_STMT.match(s):
            continue

        m = re.match(r'^if\s+(A\[.*|not\s*\(\s*-A\[31\]\s*\)|M\s*==.*|M\s*~=.*)\s*then\s*$', s)
        if m:
            continue
        kept.append(s)

    out = []
    depth = 0
    pending = False
    for ln in kept:
        toks = re.findall(r'[A-Za-z_]\w*', ln)
        first = toks[0] if toks else ''
        if first in ('end', 'until'):
            if depth > 0:
                depth -= 1
                pending = False
                out.append(ln)

            continue
        if first == 'else':
            if depth > 0:
                out.append(ln)

                for tok in toks[1:]:
                    if tok in ('for', 'while'):
                        depth += 1
                        pending = True
                    elif tok == 'do':
                        if pending:
                            pending = False
                        else:
                            depth += 1
                    elif tok in ('if', 'function', 'repeat'):
                        depth += 1
                        pending = False
                    elif tok in ('end', 'until'):
                        depth -= 1
                        pending = False
                    else:
                        pending = False

            continue
        out.append(ln)
        for tok in toks:
            if tok in ('for', 'while'):
                depth += 1
                pending = True
            elif tok == 'do':
                if pending:
                    pending = False
                else:
                    depth += 1
            elif tok in ('if', 'function', 'repeat'):
                depth += 1
                pending = False
            elif tok in ('end', 'until'):
                depth -= 1
                pending = False
            else:
                pending = False

    while out and out[0].strip() in ('else', 'else;'):
        del out[0]
    kept = out

    depth = 0
    for ln in kept:
        for tok in re.findall(r'[A-Za-z_]\w*', ln):
            if tok in ('function', 'if', 'for', 'while', 'repeat'):

                depth += 1
            elif tok in ('end', 'until'):
                depth -= 1
    while depth < 0 and kept:
        for i in range(len(kept) - 1, -1, -1):
            if kept[i].strip() in ('end', 'end;'):
                del kept[i]
                depth += 1
                break
        else:
            break

    while kept and kept[0].strip() in ('else', 'else;'):
        del kept[0]
    return kept

JUMP_RE = re.compile(r'\bG\s*=\s*\(?\s*(D|i|w)\[G\]\s*\)?')
COND_RE = re.compile(r'^\s*if\b')

def classify(core_lines: list):
    text = '\n'.join(core_lines)
    jumps = JUMP_RE.findall(text)
    is_cond = bool(COND_RE.search(text)) and ('else' in text or 'if' in text)
    is_ret = bool(re.search(r'(^|\n)\s*return\b', text))

    if jumps and is_cond:
        return ('cjump', jumps[-1])
    if jumps and not is_ret and len(core_lines) <= 4:

        writes_d = bool(re.search(r'\(d\)|d\[', text))
        if not writes_d:
            return ('jump', jumps[-1])

        if re.fullmatch(r'\s*G\s*=\s*\(?\s*(D|i|w)\[G\]\s*\)?\s*;?\s*', text):
            return ('jump', jumps[-1])
    if is_ret:
        return ('ret', None)
    if jumps:

        return ('other', None)
    return ('other', None)

def substitute(text: str, vals: dict) -> str:
    def rep(m):
        name = m.group(1)
        v = vals.get(name, '-')
        return fmt_val(v)

    text = re.sub(r'\b(t|i|w|D|f|O|z)\[G\]', rep, text)

    text = re.sub(r'\(D\)', 'D_arr', text)
    text = re.sub(r'\bD_arr\b', 'D_arr', text)
    return text

def block_balance(lines: list) -> int:
    """Net block depth. for/while consume the following do (see a49_dispatch)."""
    depth = 0
    pending = False
    for ln in lines:
        for tok in re.findall(r'[A-Za-z_]\w*', ln):
            if tok in ('for', 'while'):
                depth += 1
                pending = True
            elif tok == 'do':
                if pending:
                    pending = False
                else:
                    depth += 1
            elif tok in ('if', 'function', 'repeat'):
                depth += 1
                pending = False
            elif tok in ('end', 'until'):
                depth -= 1
                pending = False
            else:
                pending = False
    return depth

def chain_max_reg(vals_list) -> int:
    mx = 0
    for vals in vals_list:
        for k in ('i', 'w', 'D'):
            v = vals.get(k, '-')
            if re.fullmatch(r'-?\d+(?:\.\d+)?', v or ''):
                try:
                    n = int(float(v))
                    if 0 <= n <= 100000 and n > mx:
                        mx = n
                except Exception:
                    pass
    return mx

BLOCK_OPEN = re.compile(
    r'^(if\b.*\bthen|elseif\b.*\bthen|else|end|do|repeat|until\b|'
    r'for\b|while\b|function\b|local\s+function\b|return\b|break)\s*.*$'
)

def emit_code(out: list, indent: str, line: str):
    """Emit one code line, ensuring `;` termination for call-like statements.

    Luau treats a newline followed by `(` as a call continuation, so a branch
    like `G=11` / `(d)[35]=...` parses as one call. Terminating simple
    statements with `;` keeps each slot independent.
    """
    s = line.strip()
    if not s:
        return
    if s.startswith('--'):
        out.append(indent + s)
        return
    if BLOCK_OPEN.match(s):
        out.append(indent + s)
        return
    if not s.endswith(';'):
        s += ';'
    out.append(indent + s)

def lift_chain(cid: int, gs: list, slots: dict, leaves: dict) -> str:

    out = []
    out.append('local function chain_%d(__env, __upvals, ...)' % cid)
    out.append('    -- %d slots' % len(gs))
    slot_vals = [slots[(cid, g)] for g in gs]
    mx = chain_max_reg(slot_vals)
    out.append('    local d = {} -- registers (r0..r%d)' % mx)
    out.append('    local A, Z, j = __env.A, __env.Z, __upvals')
    out.append('    local I = {} -- open captures')
    out.append('    local K, T, q, n, g, b, v, e, h, o, a, S, L, U, W, E, X, N, r, u, M, P, D_arr')
    out.append('    local G = 1')
    out.append('    while true do')
    gset = set(gs)

    CHUNK = 64
    ngroups = (len(gs) + CHUNK - 1) // CHUNK or 1
    for idx, g in enumerate(gs):

        if idx % CHUNK == 0 and ngroups > 1:
            lo = g
            hi = gs[min(idx + CHUNK, len(gs)) - 1]
            rng = ('G >= %d and G <= %d' % (lo, hi)) if hi > lo else ('G == %d' % lo)
            out.append('        %s %s then' % ('if' if idx == 0 else 'elseif', rng))
            kw = 'if'
        else:
            kw = 'if' if idx == 0 else 'elseif'
        vals = slots[(cid, g)]
        try:
            P = int(float(vals['t'])) if re.fullmatch(r'-?\d+(?:\.\d+)?', vals['t'] or '') else -1
        except Exception:
            P = -1
        raw = leaves.get(P, '-- no leaf for opcode %s' % vals['t'])
        core = clean_leaf(raw) if not raw.lstrip().startswith('-- no leaf') else [raw]

        cut = []
        for ln in core:
            cut.append(ln)
            if re.match(r'^\s*return\b', ln):
                break
        core = cut
        sub = []
        for ln in core:
            s = substitute(ln, vals)

            s = re.sub(r';\s*;', ';', s).strip()
            s = re.sub(r'^;+', '', s).strip()
            if s:
                sub.append(s)
        ops = ' '.join('%s=%s' % (f, vals[f]) for f in ('i', 'w', 'D', 'f', 'O', 'z') if vals[f] != '-')
        ops = comment_safe(ops)

        sub = [re.sub(r"^G\s*=\s*\(?\s*(\d+)\s*\)?\s*;?$",
                      lambda m: "G=%d;" % (int(m.group(1)) + 1), ln) for ln in sub]
        out.append('        %s G == %d then' % (kw, g))
        out.append('            -- [%d:%d] op=%s %s' % (cid, g, vals['t'], ops))
        has_ret = bool(re.search(r'(^|\n)\s*return\b', '\n'.join(sub)))
        if not sub:
            out.append('            -- (vm bookkeeping only)')
        elif block_balance(sub) != 0:
            out.append('            -- unbalanced leaf op=%s (raw: opcodes/%03d.lua), kept as comment:' % (vals['t'], P if P >= 0 else 0))
            for ln in sub:

                safe = comment_safe(ln.replace(']]', '] ]').replace('[[', '[ ['))
                out.append('            -- | ' + safe)
        else:
            for ln in sub:
                emit_code(out, '            ', ln)
        if has_ret:
            pass
        else:
            nxt = gs[idx + 1] if idx + 1 < len(gs) else None
            if nxt is not None:
                out.append('            if G == %d then G = %d end' % (g, nxt))
            else:
                out.append('            break')
        out.append('')
        if ngroups > 1 and (idx + 1) % CHUNK == 0 and idx + 1 < len(gs):
            out.append('        end')
    if ngroups > 1:
        out.append('        end')
    out.append('        else')
    out.append('            break')
    out.append('        end')
    out.append('    end')
    out.append('end')
    return '\n'.join(out)

def main() -> int:
    work = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent / 'work'
    dest = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else work / 'lifted.lua'
    PROFILE.update(detect_profile(work))
    slots, order = load_slots(work)
    leaves = load_leaves(work)
    if not slots:
        print('no chains in %s' % (work / 'chains.tsv'), file=sys.stderr)
        return 2
    total = sum(len(v) for v in order.values())
    print('chains=%d slots=%d leaves=%d' % (len(order), total, len(leaves)))
    parts = []
    parts.append('-- Deobfuscated by OmniDBF (Luraph v14.7 lifter v1)')
    parts.append('-- Detected obfuscation: Luraph v14.7')
    parts.append('-- program: %d functions (chains), %d instructions' % (len(order), total))
    parts.append('-- style: v15-like readable Luau; registers as d[r], control as while-dispatch.')
    parts.append('-- next step toward full v15 parity: structure dispatch into if/while and')
    parts.append('-- recover real locals via deobf/backend.py (see LURAPH14.md "Still open").')
    parts.append('')
    for cid in sorted(order):
        parts.append(lift_chain(cid, order[cid], slots, leaves))
        parts.append('')
    dest.write_text('\n'.join(parts), encoding='utf-8')
    print('wrote %s (%d chars)' % (dest, len('\n'.join(parts))))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
