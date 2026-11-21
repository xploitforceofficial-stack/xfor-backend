from __future__ import annotations
from typing import List, Any, Optional, Dict, Set, Tuple
from dataclasses import dataclass, field

from .deserializer import Chunk, Instruction
from .hercules_opcode import OP_NAME_BY_NUM, OP_TYPES, is_k, indexk, BITRK

ANTITAMPER_PATTERNS = [
    "Tamper Detected! Reason:",
    "Critical function removed",
    "Critical function type changed",
    "Metamethod tampered",
    "Debug library incomplete",
    "Protected By Hercules",
]

def _proto_is_antitamper(chunk: Chunk) -> bool:

    if not chunk.Constants:
        return False

    if len(chunk.Constants) > 20:
        return False
    antitamper_count = 0
    for c in chunk.Constants:
        if isinstance(c, str) and any(p in c for p in ANTITAMPER_PATTERNS):
            antitamper_count += 1

    return antitamper_count > 0 and antitamper_count > len(chunk.Constants) // 2

_CAESAR_MARKER_CONSTS = {"byte", "char", "insert", "concat"}
_CAESAR_MARKER_NUMS = {48, 57, 65, 90, 97, 122, 10, 26}

def _caesar_decode(text: str, shift: int) -> str:

    result = []
    for ch in text:
        b = ord(ch)
        if 48 <= b <= 57:
            result.append(chr(((b - 48 - shift + 10) % 10) + 48))
        elif 65 <= b <= 90:
            result.append(chr(((b - 65 - shift + 26) % 26) + 65))
        elif 97 <= b <= 122:
            result.append(chr(((b - 97 - shift + 26) % 26) + 97))
        else:
            result.append(ch)
    return "".join(result)

def _try_const_fold_call(fn_expr: str, args: List[str]) -> Optional[str]:

    if fn_expr.startswith("<elided_proto_") and len(args) == 2:

        encoded_str = _extract_string_literal(args[0])
        shift_val = _extract_number(args[1])
        if encoded_str is not None and shift_val is not None:
            try:
                decoded = _caesar_decode(encoded_str, int(shift_val))
                return _fmt_const(decoded)
            except Exception:
                pass
    return None

def _extract_string_literal(expr: str) -> Optional[str]:

    expr = expr.strip()
    if len(expr) >= 2 and expr[0] == '"' and expr[-1] == '"':

        inner = expr[1:-1]
        return inner.replace('\\"', '"').replace('\\\\', '\\').replace('\\n', '\n').replace('\\t', '\t')
    return None

def _extract_number(expr: str) -> Optional[float]:

    expr = expr.strip()
    try:
        return float(expr)
    except ValueError:
        return None

def _is_caesar_decoder(chunk: Chunk) -> bool:

    if not chunk.Constants:
        return False
    strs = set()
    nums = set()
    for c in chunk.Constants:
        if isinstance(c, str):
            strs.add(c)
        elif isinstance(c, (int, float)):
            nums.add(int(c))
    if not _CAESAR_MARKER_CONSTS.issubset(strs):
        return False
    common = nums & _CAESAR_MARKER_NUMS
    if len(common) < 5:
        return False
    return True

import json as _json

def _build_table_marker(d: dict) -> str:

    parts = []
    for k, v in d.items():

        if isinstance(k, float) and k == int(k):
            k = int(k)
        parts.append(f"{_json.dumps(k)}:{_json.dumps(v)}")
    return "@TABLE{" + ",".join(parts) + "}"

def _parse_table_marker(expr: str) -> dict:

    if not expr.startswith("@TABLE{") or not expr.endswith("}"):
        return {}
    inner = expr[len("@TABLE{"):-1]
    if not inner:
        return {}
    d = {}
    for part in inner.split(","):
        if ":" in part:
            k_str, v_str = part.split(":", 1)
            try:
                k = _json.loads(k_str)
                v = _json.loads(v_str)

                if isinstance(k, float) and k == int(k):
                    k = int(k)
                d[k] = v
            except Exception:
                pass
    return d

def _try_parse_value(expr: str):

    expr = expr.strip()
    if expr.startswith('"') and expr.endswith('"'):
        try:
            return _json.loads(expr)
        except Exception:
            return None
    try:
        if '.' in expr:
            return float(expr)
        return int(expr)
    except ValueError:
        return None

def _fmt_const(v: Any) -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e15:
            return str(int(v))
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        out = ['"']
        for ch in v:
            if ch == '"':
                out.append('\\"')
            elif ch == "\\":
                out.append("\\\\")
            elif ch == "\n":
                out.append("\\n")
            elif ch == "\r":
                out.append("\\r")
            elif ch == "\t":
                out.append("\\t")
            elif 32 <= ord(ch) < 127:
                out.append(ch)
            else:
                out.append(f"\\{ord(ch)}")
        out.append('"')
        return "".join(out)
    return repr(v)

def _is_ident(s: str) -> bool:
    if not s:
        return False
    if not (s[0].isalpha() or s[0] == "_"):
        return False
    return all(ch.isalnum() or ch == "_" for ch in s[1:])

@dataclass
class RegState:
    values: Dict[int, str] = field(default_factory=dict)
    declared: Set[int] = field(default_factory=set)

    def get(self, r: Optional[int]) -> str:
        if r is None:
            return "?"
        return self.values.get(r, f"R{r}")

    def set(self, r: int, expr: str) -> None:
        self.values[r] = expr

    def kill(self, r: int) -> None:
        self.values.pop(r, None)
        self.declared.discard(r)

    def kill_range(self, start: int, end: int) -> None:
        for r in range(start, end + 1):
            self.kill(r)

class UpvalResolver:
    def __init__(self):
        self.resolved: Dict[Tuple[int, int], str] = {}
        self._counter = 0

    def register(self) -> int:
        cid = self._counter
        self._counter += 1
        return cid

    def bind(self, cid: int, idx: int, expr: str) -> None:
        self.resolved[(cid, idx)] = expr

    def resolve(self, cid: int, idx: int, fallback: str) -> str:
        return self.resolved.get((cid, idx), fallback)

class DecompilerV2:
    def __init__(self, chunk: Chunk, parent: Optional["DecompilerV2"] = None,
                 name: str = "main", uv: Optional[UpvalResolver] = None,
                 uv_idx: int = 0):
        self.chunk = chunk
        self.parent = parent
        self.name = name
        self.children: List[DecompilerV2] = []
        self.uv = uv or UpvalResolver()
        self.cid = self.uv.register()
        self._uv_idx = uv_idx
        for i, sub in enumerate(chunk.Protos):
            self.children.append(DecompilerV2(sub, self, f"{name}.P{i}", self.uv, i))

    def _depth(self) -> int:
        d = 0
        p = self.parent
        while p:
            d += 1
            p = p.parent
        return d

    def decompile(self) -> str:
        insts = self.chunk.Instructions
        n = len(insts)
        depth = self._depth()
        ind = "    " * depth

        reg = RegState()
        counter = [0]
        lines: List[str] = []

        elided_protos: Set[int] = set()
        for idx, sub in enumerate(self.chunk.Protos):
            if _proto_is_antitamper(sub) or _is_caesar_decoder(sub):
                elided_protos.add(idx)

        for i in range(self.chunk.Parameters):
            reg.declared.add(i)
            reg.set(i, f"a{i + 1}")

        i = 0

        last_return = -1
        if self.parent is None:
            for ri in range(len(insts) - 1, -1, -1):
                if insts[ri].opname in ("RETURN", "RETURN0", "RETURN1"):
                    last_return = ri
                    break

        while i < n:
            inst = insts[i]
            opname = inst.opname

            if opname in ("EQ", "LT", "LE"):
                a_val = self._rk(inst, inst.B, reg, True)
                b_val = self._rk(inst, inst.C, reg, False)
                if a_val == b_val and a_val not in ("?", ):

                    i += 2
                    if inst.A == 1:

                        pass
                    continue

            line = self._handle(inst, i, insts, reg, counter, ind, elided_protos)
            if line:
                lines.append(f"{ind}{line}")
            i += 1

            if opname == "CLOSURE":
                sub_idx = inst.F or 0
                if 0 <= sub_idx < len(self.chunk.Protos):
                    n_up = self.chunk.Protos[sub_idx].Upvals
                    for u in range(n_up):
                        if i >= n:
                            break
                        upinst = insts[i]
                        if upinst.opname == "MOVE":
                            expr = reg.get(upinst.B)
                            self.uv.bind(self.children[sub_idx].cid, u, expr)
                        elif upinst.opname == "GETUPVAL":
                            parent_idx = upinst.B or 0
                            parent_expr = self.uv.resolve(self.cid, parent_idx, f"<upvalue:{parent_idx}>")
                            self.uv.bind(self.children[sub_idx].cid, u, parent_expr)
                        i += 1

                    if hasattr(self, '_pending_closure') and self._pending_closure:
                        psub, pfname, pind = self._pending_closure
                        self._pending_closure = None
                        if psub == sub_idx and psub not in elided_protos:
                            child = self.children[sub_idx]
                            body = child.decompile()
                            body_lines = body.splitlines() if body else []

                            if lines and lines[-1].endswith("-- body below"):
                                lines.pop()
                            lines.append(f"{pind}local {pfname} = function(...)")
                            for bl in body_lines:

                                if bl.strip():
                                    lines.append(f"{pind}    {bl}")
                                else:
                                    lines.append("")
                            lines.append(f"{pind}end")

        return "\n".join(lines)

    def _rk(self, inst: Instruction, value: Optional[int], reg: RegState, is_b: bool) -> str:
        if value is None:
            return "?"

        flag = inst.s if is_b else inst.a
        resolved = inst.L if is_b else inst.R
        if flag and resolved is not None:
            return _fmt_const(resolved)
        if is_k(value):
            idx = indexk(value)
            if 0 <= idx < len(self.chunk.Constants):
                return _fmt_const(self.chunk.Constants[idx])
            return f"K{idx}"
        return reg.get(value)

    def _handle(self, inst: Instruction, pc: int, insts: List[Instruction],
                reg: RegState, counter: List[int], ind: str,
                elided_protos: Set[int]) -> str:
        opname = inst.opname
        A = inst.A
        B = inst.B
        C = inst.C
        consts = self.chunk.Constants

        def rk_b() -> str:
            return self._rk(inst, B, reg, True)

        def rk_c() -> str:
            return self._rk(inst, C, reg, False)

        def decl(expr: str, hint: Optional[str] = None) -> str:
            if hint is None:
                hint = f"v{counter[0]}"
                counter[0] += 1
            reg.declared.add(A)

            reg.set(A, expr)
            return f"local {hint} = {expr}"

        def assign_or_decl(expr: str) -> str:
            if A in reg.declared:
                cur = reg.values.get(A, f"R{A}")
                if cur == expr:
                    return ""
                reg.set(A, expr)

                return f"{cur} = {expr}" if not cur.startswith("@") else ""
            return decl(expr)

        if opname == "MOVE":
            return assign_or_decl(reg.get(B))
        if opname == "LOADK":
            if inst.g and inst.D is not None:
                return assign_or_decl(_fmt_const(inst.D))
            return assign_or_decl(f"K{inst.F or 0}")
        if opname == "LOADBOOL":
            val = "true" if B else "false"
            return assign_or_decl(val)
        if opname == "LOADNIL":
            return assign_or_decl("nil")
        if opname == "GETGLOBAL":

            name = _fmt_const(inst.D) if inst.D is not None else f"K{inst.F or 0}"

            if name.startswith('"') and name.endswith('"'):
                inner = name[1:-1]
                if _is_ident(inner):
                    name = inner

            reg.set(A, name)
            return ""

        if opname == "GETUPVAL":
            expr = self.uv.resolve(self.cid, B or 0, f"<upvalue:{B}>")
            return assign_or_decl(expr)
        if opname == "SETUPVAL":
            expr = self.uv.resolve(self.cid, B or 0, f"<upvalue:{B}>")
            return f"{expr} = {reg.get(A)}"

        if opname == "NEWTABLE":

            reg.set(A, "@TABLE{}")
            return ""
        if opname == "GETTABLE":

            table_expr = reg.get(B)
            if table_expr.startswith("@TABLE{"):

                table_dict = _parse_table_marker(table_expr)

                key = None
                if inst.a and inst.R is not None:
                    key = inst.R
                elif is_k(C):
                    idx = indexk(C)
                    if 0 <= idx < len(consts):
                        key = consts[idx]
                elif C is not None and not is_k(C):

                    key_expr = reg.get(C)
                    key = _try_parse_value(key_expr)
                if key is not None and key in table_dict:
                    return assign_or_decl(_fmt_const(table_dict[key]))
            return assign_or_decl(f"{reg.get(B)}[{rk_c()}]")
        if opname == "SETTABLE":

            table_expr = reg.get(A)
            if table_expr.startswith("@TABLE{"):
                table_dict = _parse_table_marker(table_expr)

                key = None
                if inst.s and inst.L is not None:
                    key = inst.L
                elif is_k(B):
                    idx = indexk(B)
                    if 0 <= idx < len(consts):
                        key = consts[idx]

                val = None
                if inst.a and inst.R is not None:
                    val = inst.R
                elif is_k(C):
                    idx = indexk(C)
                    if 0 <= idx < len(consts):
                        val = consts[idx]
                if key is not None and val is not None:
                    table_dict[key] = val
                    reg.set(A, _build_table_marker(table_dict))
                    return ""
            return f"{reg.get(A)}[{rk_b()}] = {rk_c()}"
        if opname == "SELF":
            obj = reg.get(B)
            method = rk_c().strip('"')
            reg.set(A + 1, obj)
            reg.set(A, f"{obj}:{method}")
            return ""

        ARITH_OPS = {"ADD": "+", "SUB": "-", "MUL": "*", "DIV": "/",
                     "MOD": "%", "POW": "^", "CONCAT": " .. "}
        if opname in ARITH_OPS:
            sym = ARITH_OPS[opname]
            expr = f"({rk_b()} {sym} {rk_c()})"
            return assign_or_decl(expr)
        if opname == "UNM":
            return assign_or_decl(f"(-{reg.get(B)})")
        if opname == "NOT":
            return assign_or_decl(f"(not {reg.get(B)})")
        if opname == "LEN":
            return assign_or_decl(f"(#{reg.get(B)})")

        COMP_OPS = {"EQ": "==", "LT": "<", "LE": "<="}
        if opname in COMP_OPS:

            return ""

        if opname == "TEST":
            return ""
        if opname == "TESTSET":
            return ""

        if opname == "JMP":
            return ""

        if opname == "CALL":

            n_args = (B - 1) if B and B > 0 else -1
            n_ret = (C - 1) if C and C > 0 else -1
            fn = reg.get(A)

            if n_args == -1:

                args = []
                consumed = []
                for r in range(A + 1, A + 20):
                    val = reg.values.get(r)
                    if val is not None:
                        args.append(val)
                        consumed.append(r)
                    else:
                        break
                if not args:
                    args_str = "..."
                else:
                    args_str = ", ".join(args)

                    for r in consumed:
                        reg.values.pop(r, None)
            else:

                if ":" in fn and not fn.startswith("("):
                    args = [reg.get(A + 2 + j) for j in range(n_args)]

                    for j in range(n_args):
                        reg.values.pop(A + 2 + j, None)
                else:
                    args = [reg.get(A + 1 + j) for j in range(n_args)]

                    for j in range(n_args):
                        reg.values.pop(A + 1 + j, None)
                args_str = ", ".join(args)

            if ":" in fn and not fn.startswith("("):
                expr = f"{fn}({args_str})"
            else:
                expr = f"{fn}({args_str})"

            if args and not n_args == -1:
                folded = _try_const_fold_call(fn, args)
                if folded is not None:
                    expr = folded

            if n_ret == 0:

                return expr
            elif n_ret == 1:

                return assign_or_decl(expr)
            elif n_ret == -1:

                reg.set(A, expr)

                return ""
            else:
                names = []
                for j in range(n_ret):
                    hint = f"v{counter[0]}"
                    counter[0] += 1
                    reg.declared.add(A + j)
                    reg.set(A + j, hint)
                    names.append(hint)
                return f"local {', '.join(names)} = {expr}"

        if opname == "TAILCALL":
            n_args = (B - 1) if B and B > 0 else 0
            fn = reg.get(A)
            if ":" in fn and not fn.startswith("("):
                args = [reg.get(A + 2 + j) for j in range(n_args)]
                return f"return {fn}({', '.join(args)})"
            args = [reg.get(A + 1 + j) for j in range(n_args)]
            return f"return {fn}({', '.join(args)})"

        if opname == "RETURN":
            n_ret = (B - 1) if B and B > 0 else 0
            if n_ret <= 0:
                return "return"
            vals = [reg.get(A + j) for j in range(n_ret)]
            return f"return {', '.join(vals)}"
        if opname == "RETURN0":
            return "return"
        if opname == "RETURN1":
            return f"return {reg.get(A)}"

        if opname == "CLOSURE":
            sub_idx = inst.F or 0
            if sub_idx in elided_protos:

                fname = f"<elided_proto_{sub_idx}>"
                reg.declared.add(A)
                reg.set(A, fname)
                return f"-- proto {sub_idx} elided (antitamper/string-decoder)"
            fname = f"fn_{self.name.replace('.', '_')}_P{sub_idx}"
            reg.declared.add(A)
            reg.set(A, fname)

            self._pending_closure = (sub_idx, fname, ind)
            return f"local {fname} = function(...)  -- body below"

        if opname == "FORPREP":
            return ""
        if opname == "FORLOOP":
            return ""
        if opname == "TFORLOOP":
            return ""
        if opname == "SETLIST":
            return ""

        if opname == "VARARG":
            return ""

        return f"-- {opname} A={A} B={B} C={C}"

def decompile_v2(chunk: Chunk) -> str:

    d = DecompilerV2(chunk)
    return d.decompile()
