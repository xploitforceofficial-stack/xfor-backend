from __future__ import annotations
from typing import List, Any, Optional
from .deserializer import Chunk, Instruction
from . import lua54_bytecode as L54
from .lua54_bytecode import (
    OP_NAME_BY_NUM_54, OP_MODE_BY_NUM_54, MAXARG_sBx,
)

def _fmt_const(v: Any) -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e15:
            return f"{int(v)}"
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

BITRK = 1 << 8

def _is_k(x: Optional[int]) -> bool:
    return x is not None and x >= BITRK

def _indexk(x: int) -> int:
    return x - BITRK

def _rk(value: Optional[int], chunk: Chunk) -> str:

    if value is None:
        return "?"
    if _is_k(value):
        idx = _indexk(value)
        if 0 <= idx < len(chunk.Constants):
            return f"K{idx}({_fmt_const(chunk.Constants[idx])})"
        return f"K{idx}"
    return f"R{value}"

def disassemble_instruction(inst: Instruction, pc: int, chunk: Chunk) -> str:
    opname = OP_NAME_BY_NUM_54.get(inst.S, f"OP_{inst.S}")
    mode = OP_MODE_BY_NUM_54.get(inst.S, "iABC")

    disp_pc = pc + 1

    if mode == "iABx":
        if opname == "LOADK":

            idx = inst.Bx if inst.Bx is not None else 0
            if 0 <= idx < len(chunk.Constants):
                return f"{disp_pc:5d}  {opname:<11} R{inst.A}  K{idx}({_fmt_const(chunk.Constants[idx])})"
            return f"{disp_pc:5d}  {opname:<11} R{inst.A}  K{idx}"
        if opname == "CLOSURE":
            idx = inst.Bx if inst.Bx is not None else 0
            return f"{disp_pc:5d}  {opname:<11} R{inst.A}  {idx}  ; to proto {idx}"
        return f"{disp_pc:5d}  {opname:<11} R{inst.A}  Bx={inst.Bx}"

    if mode == "iAsBx":

        sBx = inst.sBx if inst.sBx is not None else 0
        target = disp_pc + sBx
        if opname == "JMP":
            return f"{disp_pc:5d}  {opname:<11} R{inst.A}  to {target}"
        return f"{disp_pc:5d}  {opname:<11} R{inst.A}  to {target}"

    if mode == "iAx":
        return f"{disp_pc:5d}  {opname:<11} Ax={inst.A}"

    A = inst.A
    B = inst.B
    C = inst.C

    if opname == "MOVE":
        return f"{disp_pc:5d}  {opname:<11} R{A}  R{B}"
    if opname == "LOADK":

        return f"{disp_pc:5d}  {opname:<11} R{A}  Bx={inst.Bx}"
    if opname in ("GETI", "GETTABLE"):
        return f"{disp_pc:5d}  {opname:<11} R{A}  R{B}  {_rk(C, chunk)}"
    if opname in ("SETI", "SETTABLE"):
        return f"{disp_pc:5d}  {opname:<11} R{A}  {_rk(B, chunk)}  {_rk(C, chunk)}"
    if opname == "GETTABUP":

        up_idx = B if B is not None else 0
        key_idx = C if C is not None else 0
        if 0 <= key_idx < len(chunk.Constants):
            return f"{disp_pc:5d}  {opname:<11} R{A}  U{up_idx}  K{key_idx}({_fmt_const(chunk.Constants[key_idx])})"
        return f"{disp_pc:5d}  {opname:<11} R{A}  U{up_idx}  K{key_idx}"
    if opname == "SETTABUP":

        up_idx = A
        return f"{disp_pc:5d}  {opname:<11} U{up_idx}  K{B}(...)  {_rk(C, chunk)}"
    if opname == "GETFIELD":

        key_idx = C if C is not None else 0
        if 0 <= key_idx < len(chunk.Constants):
            return f"{disp_pc:5d}  {opname:<11} R{A}  R{B}  K{key_idx}({_fmt_const(chunk.Constants[key_idx])})"
        return f"{disp_pc:5d}  {opname:<11} R{A}  R{B}  K{key_idx}"
    if opname == "SETFIELD":

        key_idx = B if B is not None else 0
        if 0 <= key_idx < len(chunk.Constants):
            return f"{disp_pc:5d}  {opname:<11} R{A}  K{key_idx}({_fmt_const(chunk.Constants[key_idx])})  {_rk(C, chunk)}"
        return f"{disp_pc:5d}  {opname:<11} R{A}  K{key_idx}  {_rk(C, chunk)}"
    if opname == "GETUPVAL":
        return f"{disp_pc:5d}  {opname:<11} R{A}  U{B}"
    if opname == "SETUPVAL":
        return f"{disp_pc:5d}  {opname:<11} U{B}  R{A}"
    if opname == "NEWTABLE":
        return f"{disp_pc:5d}  {opname:<11} R{A}  {B}  {C}"
    if opname == "SELF":
        return f"{disp_pc:5d}  {opname:<11} R{A}  R{B}  {_rk(C, chunk)}"
    if opname in ("ADD","SUB","MUL","MOD","POW","DIV","IDIV","BAND","BOR","BXOR","SHL","SHR","CONCAT"):
        return f"{disp_pc:5d}  {opname:<11} R{A}  {_rk(B, chunk)}  {_rk(C, chunk)}"
    if opname in ("ADDI","SHRI","SHLI"):
        return f"{disp_pc:5d}  {opname:<11} R{A}  R{B}  {C if C is not None else 0}  ; imm"
    if opname in ("ADDK","SUBK","MULK","MODK","POWK","DIVK","IDIVK","BANDK","BORK","BXORK"):

        idx = C if C is not None else 0
        if 0 <= idx < len(chunk.Constants):
            return f"{disp_pc:5d}  {opname:<11} R{A}  R{B}  K{idx}({_fmt_const(chunk.Constants[idx])})"
        return f"{disp_pc:5d}  {opname:<11} R{A}  R{B}  K{idx}"
    if opname in ("MMBIN","MMBINI","MMBINK"):
        return f"{disp_pc:5d}  {opname:<11} R{A}  R{B}  {C}  ; metamethod"
    if opname in ("UNM","BNOT","NOT","LEN"):
        return f"{disp_pc:5d}  {opname:<11} R{A}  R{B}"
    if opname in ("CLOSE","TBC"):
        return f"{disp_pc:5d}  {opname:<11} R{A}"
    if opname in ("EQ","LT","LE"):
        return f"{disp_pc:5d}  {opname:<11} R{A}  {_rk(B, chunk)}  {_rk(C, chunk)}"
    if opname in ("EQK",):

        idx = B if B is not None else 0
        if 0 <= idx < len(chunk.Constants):
            return f"{disp_pc:5d}  {opname:<11} R{A}  K{idx}({_fmt_const(chunk.Constants[idx])})  {C}"
        return f"{disp_pc:5d}  {opname:<11} R{A}  K{idx}  {C}"
    if opname in ("EQI","LTI","LEI","GTI","GEI"):
        return f"{disp_pc:5d}  {opname:<11} R{A}  R{B}  {C}  ; imm compare"
    if opname == "TEST":
        return f"{disp_pc:5d}  {opname:<11} R{A}  {C}"
    if opname == "TESTSET":
        return f"{disp_pc:5d}  {opname:<11} R{A}  R{B}  {C}"
    if opname == "CALL":
        n_args = (B - 1) if B is not None else 0
        n_ret = (C - 1) if C is not None else 0
        return f"{disp_pc:5d}  {opname:<11} R{A}  {n_args}  {n_ret}"
    if opname == "TAILCALL":
        n_args = (B - 1) if B is not None else 0
        return f"{disp_pc:5d}  {opname:<11} R{A}  {n_args}"
    if opname == "RETURN":
        n_ret = (B - 1) if B is not None else 0
        return f"{disp_pc:5d}  {opname:<11} R{A}  {n_ret}"
    if opname == "RETURN0":
        return f"{disp_pc:5d}  {opname:<11}"
    if opname == "RETURN1":
        return f"{disp_pc:5d}  {opname:<11} R{A}"
    if opname in ("FORLOOP","FORPREP"):
        sBx = inst.sBx if inst.sBx is not None else 0
        target = disp_pc + sBx
        return f"{disp_pc:5d}  {opname:<11} R{A}  to {target}"
    if opname in ("TFORPREP","TFORLOOP"):
        sBx = inst.sBx if inst.sBx is not None else 0
        target = disp_pc + sBx
        return f"{disp_pc:5d}  {opname:<11} R{A}  to {target}"
    if opname == "TFORCALL":
        return f"{disp_pc:5d}  {opname:<11} R{A}  {B}  {C}"
    if opname == "SETLIST":
        return f"{disp_pc:5d}  {opname:<11} R{A}  {B}  {C}"
    if opname == "CLOSURE":
        idx = inst.Bx if inst.Bx is not None else 0
        return f"{disp_pc:5d}  {opname:<11} R{A}  {idx}  ; to proto {idx}"
    if opname == "VARARG":
        return f"{disp_pc:5d}  {opname:<11} R{A}  {C}"
    if opname == "VARARGPREP":
        return f"{disp_pc:5d}  {opname:<11} {A}"
    if opname == "EXTRAARG":

        return f"{disp_pc:5d}  {opname:<11} Ax={inst.A}"
    return f"{disp_pc:5d}  {opname:<11} A={A} B={B} C={C}"

def disassemble_chunk(chunk: Chunk, name: str = "main", depth: int = 0) -> List[str]:

    out: List[str] = []
    indent = "  " * depth
    src = getattr(chunk, "source", None) or "?"
    n_inst = len(chunk.Instructions)
    n_const = len(chunk.Constants)
    n_proto = len(chunk.Protos)
    n_up = chunk.Upvals
    n_params = chunk.Parameters
    maxstack = chunk.MaxStack
    out.append(
        f"{indent}{name} <{src}> ({n_inst} instructions)"
    )
    out.append(
        f"{indent}{n_params}{'+' if getattr(chunk, 'is_vararg', False) else ''} params, "
        f"{maxstack} slots, {n_up} upvalues, "
        f"0 locals, {n_const} constants, {n_proto} functions"
    )
    if chunk.Constants:
        for i, c in enumerate(chunk.Constants):
            out.append(f"{indent}  K{i}: {_fmt_const(c)}")
    if chunk.UpvalueDescs:
        for i, uv in enumerate(chunk.UpvalueDescs):
            out.append(f"{indent}  U{i}: instack={uv['instack']} idx={uv['idx']} kind={uv['kind']} name={uv.get('name')!r}")
    if chunk.Instructions:
        for i, inst in enumerate(chunk.Instructions):
            out.append(f"{indent}  {disassemble_instruction(inst, i, chunk)}")
    for i, sub in enumerate(chunk.Protos):
        out.append("")
        out.extend(disassemble_chunk(sub, f"{name}.P{i}", depth + 1))
    return out

def disassemble(chunk: Chunk) -> str:

    return "\n".join(disassemble_chunk(chunk))
