from __future__ import annotations
from typing import List, Any, Optional, Dict, Tuple, Set
from dataclasses import dataclass, field
from .deserializer import Chunk, Instruction
from .hercules_opcode import OP_NAME_BY_NUM, OP_TYPES

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
    antitamper_count = sum(1 for c in chunk.Constants
                          if isinstance(c, str) and any(p in c for p in ANTITAMPER_PATTERNS))
    return antitamper_count > 0 and antitamper_count > len(chunk.Constants) // 2

def _main_has_antitamper(chunk: Chunk) -> bool:
    return any(isinstance(c, str) and any(p in c for p in ANTITAMPER_PATTERNS)
               for c in chunk.Constants)

@dataclass
class RegState:
    values: Dict[int, str] = field(default_factory=dict)
    declared: Set[int] = field(default_factory=set)
    self_obj: Dict[int, str] = field(default_factory=dict)
    self_skip: Dict[int, int] = field(default_factory=dict)

    def get(self, r: Optional[int]) -> str:
        if r is None:
            return "?"
        return self.values.get(r, "nil")

    def set(self, r: int, expr: str) -> None:
        self.values[r] = expr

    def kill(self, r: int) -> None:
        self.values.pop(r, None)
        self.declared.discard(r)
        self.self_obj.pop(r, None)
        self.self_skip.pop(r, None)

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

def _rk(inst: Instruction, reg: RegState, is_b: bool) -> str:
    if is_b:
        if inst.s and inst.L is not None:
            return _fmt_const(inst.L)
        return reg.get(inst.B)
    else:
        if inst.a and inst.R is not None:
            return _fmt_const(inst.R)
        return reg.get(inst.C)

class UpvalueResolver:
    def __init__(self):
        self.resolved: Dict[Tuple[int, int], str] = {}
        self._counter = 0

    def register_chunk(self) -> int:
        cid = self._counter
        self._counter += 1
        return cid

    def resolve(self, chunk_id: int, uv_index: int, fallback: str) -> str:
        return self.resolved.get((chunk_id, uv_index), fallback)

    def bind(self, chunk_id: int, uv_index: int, expr: str) -> None:
        self.resolved[(chunk_id, uv_index)] = expr

class Decompiler:
    def __init__(self, chunk: Chunk, parent: Optional["Decompiler"] = None,
                 name: str = "main", uv_resolver: Optional[UpvalueResolver] = None,
                 uv_index: int = 0):
        self.chunk = chunk
        self.parent = parent
        self.name = name
        self.children: List[Decompiler] = []
        self.uv_resolver = uv_resolver or UpvalueResolver()
        self.chunk_id = self.uv_resolver.register_chunk()
        self._uv_index = uv_index
        for i, sub in enumerate(chunk.Protos):
            self.children.append(Decompiler(sub, self, f"{name}.P{i}", self.uv_resolver, i))

    def _depth(self) -> int:
        d = 0
        p = self.parent
        while p:
            d += 1
            p = p.parent
        return d

    def decompile(self) -> str:
        out_lines: List[str] = []
        insts = self.chunk.Instructions
        n = len(insts)
        depth = self._depth()
        ind = "    " * depth

        antitamper_proto_indices: Set[int] = set()
        if _main_has_antitamper(self.chunk):
            for idx, sub in enumerate(self.chunk.Protos):
                if _proto_is_antitamper(sub):
                    antitamper_proto_indices.add(idx)

        user_code_start = self._find_user_code_start(antitamper_proto_indices)

        reg = RegState()
        local_counter = [0]
        i = user_code_start if self.parent is None else 0
        elided_any = False
        seen_return = False

        while i < n:
            inst = insts[i]
            op = inst.opname

            if seen_return and self.parent is None:
                break

            if op == "CLOSURE":
                sub_idx = inst.F or 0
                if sub_idx in antitamper_proto_indices:
                    elided_any = True
                    if 0 <= sub_idx < len(self.chunk.Protos):
                        ups = self.chunk.Protos[sub_idx].Upvals
                        i += 1 + ups
                    else:
                        i += 1
                    if i < n and insts[i].opname == "CALL":
                        i += 1
                    if i + 1 < n and insts[i].opname in ("TEST", "EQ", "LT", "LE"):
                        i += 2
                        skip_count = 0
                        while i < n and skip_count < 6:
                            if insts[i].opname == "CALL":
                                i += 1
                                break
                            i += 1
                            skip_count += 1
                    continue

            line = self._emit(inst, i, insts, reg, depth, local_counter)
            if line:
                if isinstance(line, list):
                    out_lines.extend(f"{ind}{l}" if l else l for l in line)
                else:
                    out_lines.append(f"{ind}{line}")
                if isinstance(line, str) and line.startswith("return"):
                    seen_return = True
            i += self._step_count(inst, i, insts)

        if elided_any and not out_lines:
            return ""

        return "\n".join(out_lines)

    def _find_user_code_start(self, antitamper_protos: Set[int]) -> int:
        insts = self.chunk.Instructions
        n = len(insts)

        at_const_indices: Set[int] = set()
        for ci, c in enumerate(self.chunk.Constants):
            if isinstance(c, str) and any(p in c for p in ANTITAMPER_PATTERNS):
                at_const_indices.add(ci)

        if not at_const_indices:
            return self._find_user_code_start_via_closures(antitamper_protos)

        last_at_loadk = -1
        for i, inst in enumerate(insts):
            if inst.opname == "LOADK" and inst.g and (inst.F or 0) in at_const_indices:
                last_at_loadk = i

        if last_at_loadk < 0:
            return 0

        last_call_idx = last_at_loadk
        for i in range(last_at_loadk + 1, min(last_at_loadk + 30, n)):
            inst = insts[i]
            op = inst.opname
            if op == "CALL":
                last_call_idx = i
            elif op == "GETGLOBAL":
                return i
            elif op == "CLOSURE":
                continue
            elif op in ("RETURN",):
                return i + 1
            elif op == "JMP":
                continue

        return last_call_idx + 1

    def _find_user_code_start_via_closures(self, antitamper_protos: Set[int]) -> int:
        insts = self.chunk.Instructions
        n = len(insts)
        last_at_idx = -1
        i = 0
        while i < n:
            inst = insts[i]
            op = inst.opname
            if op == "CLOSURE" and (inst.F or 0) in antitamper_protos:
                last_at_idx = max(last_at_idx, i)
                sub_idx = inst.F or 0
                if 0 <= sub_idx < len(self.chunk.Protos):
                    ups = self.chunk.Protos[sub_idx].Upvals
                    last_at_idx = max(last_at_idx, i + ups)
                    i += 1 + ups
                else:
                    i += 1
                if i < n and insts[i].opname == "CALL":
                    last_at_idx = max(last_at_idx, i)
                    i += 1
                if i + 1 < n and insts[i].opname in ("TEST", "EQ", "LT", "LE"):
                    last_at_idx = max(last_at_idx, i + 1)
                    i += 2
                    skip_count = 0
                    while i < n and skip_count < 8:
                        last_at_idx = max(last_at_idx, i)
                        if insts[i].opname == "CALL":
                            i += 1
                            break
                        i += 1
                        skip_count += 1
                continue
            i += 1
        return last_at_idx + 1 if last_at_idx >= 0 else 0

    def _step_count(self, inst: Instruction, i: int, insts: List[Instruction]) -> int:
        op = inst.opname
        if op in ("EQ", "LT", "LE", "TEST", "TESTSET"):
            if i + 1 < len(insts) and insts[i + 1].opname == "JMP":
                return 2
            return 1
        if op == "CLOSURE":
            sub_idx = inst.F or 0
            if 0 <= sub_idx < len(self.chunk.Protos):
                ups = self.chunk.Protos[sub_idx].Upvals
                return 1 + ups
            return 1
        return 1

    def _new_local(self, local_counter: List[int]) -> str:
        local_counter[0] += 1
        return f"v{local_counter[0]}"

    def _is_local_name(self, name: str) -> bool:

        if not name or not name.startswith("v"):
            return False
        rest = name[1:]
        return rest.isdigit() and len(rest) > 0

    def _emit(self, inst: Instruction, i: int, insts: List[Instruction],
              reg: RegState, depth: int, local_counter: List[int]) -> Any:
        op = inst.opname

        if op == "MOVE":
            if i > 0 and insts[i - 1].opname == "CLOSURE":
                prev = insts[i - 1]
                sub_idx = prev.F or 0
                if 0 <= sub_idx < len(self.chunk.Protos):
                    sub_decomp = self.children[sub_idx]
                    uv_idx = 0
                    for j in range(i - 1 + 1, i):
                        if insts[j].opname in ("MOVE", "GETUPVAL"):
                            uv_idx += 1
                    expr = reg.get(inst.B)
                    self.uv_resolver.bind(sub_decomp.chunk_id, uv_idx, expr)
                return None
            reg.set(inst.A, reg.get(inst.B))
            return None

        if op == "LOADK":
            if inst.g and inst.D is not None:
                expr = _fmt_const(inst.D)
            elif inst.s and inst.L is not None:
                expr = _fmt_const(inst.L)
            elif inst.F is not None and 0 <= inst.F < len(self.chunk.Constants):
                expr = _fmt_const(self.chunk.Constants[inst.F])
            else:
                expr = "nil"
            reg.set(inst.A, expr)
            return None

        if op == "LOADBOOL":
            val = "true" if inst.B else "false"
            reg.set(inst.A, val)
            return None

        if op == "LOADNIL":
            for r in range(inst.A, inst.A + (inst.B or 1)):
                reg.set(r, "nil")
            return None

        if op == "GETGLOBAL":
            name = inst.D if (inst.g and inst.D is not None) else f"K{inst.F}"
            if isinstance(name, str) and _is_ident(name):
                reg.set(inst.A, name)
            else:
                reg.set(inst.A, f"_G[{_fmt_const(name)}]")
            return None

        if op == "SETGLOBAL":
            val = reg.get(inst.A)
            name = inst.D if (inst.g and inst.D is not None) else f"K{inst.F}"
            if isinstance(name, str) and _is_ident(name):
                return f"{name} = {val}"
            return f"_G[{_fmt_const(name)}] = {val}"

        if op == "GETUPVAL":
            expr = self.uv_resolver.resolve(self.chunk_id, inst.B or 0,
                                            f"<upvalue:{inst.B}>")
            reg.set(inst.A, expr)
            return None

        if op == "SETUPVAL":
            expr = reg.get(inst.A)
            return f"-- <upvalue:{inst.B}> = {expr}"

        if op == "GETTABLE":
            t = reg.get(inst.B)
            k = _rk(inst, reg, False)
            reg.set(inst.A, f"{t}[{k}]")
            return None

        if op == "SETTABLE":
            t = reg.get(inst.A)
            k = _rk(inst, reg, True)
            v = _rk(inst, reg, False)
            return f"{t}[{k}] = {v}"

        if op == "NEWTABLE":
            name = self._new_local(local_counter)
            reg.set(inst.A, name)
            reg.declared.add(inst.A)
            return f"local {name} = {{}}"

        if op == "SELF":
            obj = reg.get(inst.B)
            if inst.a and inst.R is not None and isinstance(inst.R, str) and _is_ident(inst.R):
                method_name = inst.R
                expr = f"{obj}:{method_name}"
            else:
                method = _rk(inst, reg, False)
                expr = f"{obj}[{method}]"
            reg.set(inst.A + 1, obj)
            reg.set(inst.A, expr)
            reg.self_obj[inst.A] = obj
            reg.self_skip[inst.A] = 1
            return None

        if op in ("ADD", "SUB", "MUL", "DIV", "MOD", "POW"):
            sym = {"ADD": "+", "SUB": "-", "MUL": "*", "DIV": "/", "MOD": "%", "POW": "^"}[op]
            lhs = _rk(inst, reg, True)
            rhs = _rk(inst, reg, False)
            reg.set(inst.A, f"({lhs} {sym} {rhs})")
            return None

        if op == "UNM":
            reg.set(inst.A, f"(-{reg.get(inst.B)})")
            return None

        if op == "NOT":
            reg.set(inst.A, f"(not {reg.get(inst.B)})")
            return None

        if op == "LEN":
            reg.set(inst.A, f"(#{reg.get(inst.B)})")
            return None

        if op == "CONCAT":
            lhs = _rk(inst, reg, True)
            rhs = _rk(inst, reg, False)
            reg.set(inst.A, f"({lhs} .. {rhs})")
            return None

        if op == "JMP":
            return None

        if op in ("EQ", "LT", "LE"):
            return self._emit_compare(inst, i, insts, reg)

        if op in ("TEST", "TESTSET"):
            return self._emit_test(inst, i, insts, reg)

        if op == "CALL":
            return self._emit_call(inst, reg, local_counter)

        if op == "TAILCALL":
            fn = reg.get(inst.A)
            args_str = self._call_args(inst, reg, local_counter)
            return f"return {fn}({args_str})"

        if op == "RETURN":
            if inst.B == 0:
                return None
            elif inst.B == 1:
                return "return"
            else:
                args = [reg.get(inst.A + k) for k in range(inst.B - 1)]
                args_str = ", ".join(args)
            return f"return {args_str}"

        if op == "FORPREP":
            init = reg.get(inst.A)
            limit = reg.get(inst.A + 1)
            step = reg.get(inst.A + 2)
            loop_var = self._new_local(local_counter)
            reg.set(inst.A, loop_var)
            reg.declared.add(inst.A)
            step_part = f", {step}" if step != "1" else ""
            return [f"for {loop_var} = {init}, {limit}{step_part} do"]

        if op == "FORLOOP":
            return "end"

        if op == "TFORLOOP":
            return "end"

        if op == "SETLIST":
            t = reg.get(inst.A)
            if inst.B and inst.B > 0:
                vals = [reg.get(inst.A + 1 + k) for k in range(inst.B)]
                if self._is_local_name(t):
                    lines = []
                    for k_idx, val in enumerate(vals):
                        lines.append(f"{t}[{k_idx + 1}] = {val}")
                    return lines if len(lines) > 1 else lines[0] if lines else None
            return None

        if op == "CLOSE":
            return None

        if op == "CLOSURE":
            sub_idx = inst.F or 0
            if sub_idx >= len(self.chunk.Protos):
                return None
            sub_decomp = self.children[sub_idx]
            ups_count = sub_decomp.chunk.Upvals
            for k in range(ups_count):
                if i + 1 + k < len(insts):
                    pseudo = insts[i + 1 + k]
                    if pseudo.opname == "MOVE":
                        expr = reg.get(pseudo.B)
                        self.uv_resolver.bind(sub_decomp.chunk_id, k, expr)
                    elif pseudo.opname == "GETUPVAL":
                        expr = self.uv_resolver.resolve(self.chunk_id, pseudo.B or 0,
                                                        f"<upvalue:{pseudo.B}>")
                        self.uv_resolver.bind(sub_decomp.chunk_id, k, expr)

            sub_src = sub_decomp.decompile()
            if sub_src.strip():
                sub_indented = "\n".join(("    " + l) if l else l for l in sub_src.splitlines())
            else:
                sub_indented = "    -- (empty body)"
            params = ", ".join(f"a{j+1}" for j in range(sub_decomp.chunk.Parameters))
            if ups_count == 0:
                expr = f"function({params})\n{sub_indented}\n{'    ' * depth}end"
            else:
                up_names = [self.uv_resolver.resolve(sub_decomp.chunk_id, k, f"<uv{k}>")
                            for k in range(ups_count)]
                ups_str = ", ".join(up_names)
                expr = f"function({params})  -- captures: {ups_str}\n{sub_indented}\n{'    ' * depth}end"
            reg.set(inst.A, expr)
            return None

        if op == "VARARG":
            return None

        return f"-- TODO: {op} A={inst.A} B={inst.B} C={inst.C}"

    def _call_args(self, inst: Instruction, reg: RegState,
                   local_counter: Optional[List[int]] = None) -> str:
        if inst.B == 0:
            return "..."
        if inst.B == 1:
            return ""
        skip = reg.self_skip.get(inst.A, 0)
        args = []
        for k in range(1 + skip, inst.B):
            val = reg.get(inst.A + k)
            args.append(val)
        return ", ".join(args)

    def _emit_call(self, inst: Instruction, reg: RegState,
                   local_counter: List[int]) -> Any:
        fn = reg.get(inst.A)
        args_str = self._call_args(inst, reg, local_counter)
        if inst.C == 0:
            name = self._new_local(local_counter)
            reg.set(inst.A, name)
            reg.declared.add(inst.A)
            return f"local {name} = {fn}({args_str})"
        if inst.C == 1:
            return f"{fn}({args_str})"
        if inst.C == 2:
            expr = f"{fn}({args_str})"
            current = reg.values.get(inst.A)

            if inst.A in reg.declared and current and self._is_local_name(current):
                reg.set(inst.A, expr)
                return f"{current} = {expr}"
            else:
                name = self._new_local(local_counter)
                reg.set(inst.A, name)
                reg.declared.add(inst.A)
                return f"local {name} = {fn}({args_str})"
        names = []
        for k in range(inst.C - 1):
            name = self._new_local(local_counter)
            names.append(name)
            reg.set(inst.A + k, name)
            reg.declared.add(inst.A + k)
        return f"local {', '.join(names)} = {fn}({args_str})"

    def _emit_compare(self, inst: Instruction, i: int, insts: List[Instruction],
                     reg: RegState) -> Any:
        op = inst.opname
        sym = {"EQ": "==", "LT": "<", "LE": "<="}[op]
        lhs = _rk(inst, reg, True)
        rhs = _rk(inst, reg, False)
        cond = f"({lhs} {sym} {rhs})"
        if inst.A == 0:
            cond = f"(not {cond})"
        return f"if {cond} then"

    def _emit_test(self, inst: Instruction, i: int, insts: List[Instruction],
                  reg: RegState) -> Any:
        op = inst.opname
        if op == "TEST":
            cond = reg.get(inst.A)
            if inst.C == 0:
                cond = f"(not {cond})"
            return f"if {cond} then"
        v = reg.get(inst.B)
        cond = v if inst.C else f"(not {v})"
        reg.set(inst.A, v)
        return f"if {cond} then"

def decompile(chunk: Chunk) -> str:
    d = Decompiler(chunk)
    body = d.decompile()
    return body
