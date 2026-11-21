from __future__ import annotations
import struct
from dataclasses import dataclass, field
from typing import List, Any, Optional, Dict

@dataclass
class Instruction:
    S: int
    A: int = 0
    B: Optional[int] = None
    C: Optional[int] = None
    Bx: Optional[int] = None
    sBx: Optional[int] = None
    F: Optional[int] = None
    f: Optional[int] = None
    s: bool = False
    a: bool = False
    g: bool = False

    D: Any = None
    L: Any = None
    R: Any = None

    @property
    def opname(self) -> str:
        from .hercules_opcode import OP_NAME_BY_NUM
        return OP_NAME_BY_NUM.get(self.S, f"OP_{self.S}")

@dataclass
class Chunk:
    Upvals: int = 0
    Parameters: int = 0
    MaxStack: int = 0
    Instructions: List[Instruction] = field(default_factory=list)
    Constants: List[Any] = field(default_factory=list)
    Protos: List["Chunk"] = field(default_factory=list)
    Parent: Optional["Chunk"] = None
    Index: int = 0

class BytecodeReader:

    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0

    def g8(self) -> int:
        v = self.data[self.pos]
        self.pos += 1
        return v

    def g16(self) -> int:
        v1, v2 = self.data[self.pos], self.data[self.pos + 1]
        self.pos += 2
        return (v2 << 8) | v1

    def g32(self) -> int:
        v1, v2, v3, v4 = (
            self.data[self.pos],
            self.data[self.pos + 1],
            self.data[self.pos + 2],
            self.data[self.pos + 3],
        )
        self.pos += 4
        return (v4 << 24) | (v3 << 16) | (v2 << 8) | v1

    def f64(self) -> float:
        v = self.data[self.pos:self.pos + 8]
        self.pos += 8
        return struct.unpack("<d", v)[0]

    def string(self) -> str:
        length = self.g32()
        s = self.data[self.pos:self.pos + length].decode("latin-1")
        self.pos += length
        return s

_MAX_SENSIBLE_SUBPROTOS = 65536

def _parse_one_constant(reader: BytecodeReader) -> Optional[Any]:

    t = reader.g8()
    if t == 1:
        return reader.g8() != 0
    if t == 3:
        return reader.f64()
    if t == 4:
        return reader.string()

    return None

def _parse_instructions(reader: BytecodeReader, count: int) -> List[Instruction]:
    insts: List[Instruction] = []
    for _ in range(count):
        Data = reader.g32()
        Sco = reader.g8()
        Type = reader.g8()
        A = reader.g16()
        ModeB = reader.g8()
        ModeC = reader.g8()
        inst = Instruction(S=Sco, A=A)
        if Type == 1:
            inst.B = reader.g16()
            inst.C = reader.g16()
            inst.s = (ModeB == 1) and (inst.B > 0xFF)
            inst.a = (ModeC == 1) and (inst.C > 0xFF)
        elif Type == 2:
            inst.Bx = reader.g32()
            inst.F = inst.Bx
            inst.g = (ModeB == 1)
        elif Type == 3:
            inst.sBx = reader.g32() - 131071
            inst.f = inst.sBx
        else:

            pass
        insts.append(inst)
    return insts

def _parse_constants(reader: BytecodeReader, count: int) -> List[Any]:

    consts: List[Any] = []
    for _ in range(count):
        consts.append(_parse_one_constant(reader))
    return consts

def _resolve_refs(chunk: Chunk) -> None:

    for inst in chunk.Instructions:
        if inst.g and inst.F is not None:
            if 0 <= inst.F < len(chunk.Constants):
                inst.D = chunk.Constants[inst.F]
        else:
            if inst.s and inst.B is not None:
                idx = inst.B - 256
                if 0 <= idx < len(chunk.Constants):
                    inst.L = chunk.Constants[idx]
            if inst.a and inst.C is not None:
                idx = inst.C - 256
                if 0 <= idx < len(chunk.Constants):
                    inst.R = chunk.Constants[idx]

def parse_chunk(reader: BytecodeReader, parent: Optional[Chunk] = None, idx: int = 0) -> Chunk:

    chunk = Chunk(
        Upvals=reader.g8(),
        Parameters=reader.g8(),
        MaxStack=reader.g8(),
        Parent=parent,
        Index=idx,
    )

    num_inst = reader.g32()
    chunk.Instructions = _parse_instructions(reader, num_inst)

    num_const = reader.g32()
    const_start_pos = reader.pos
    chunk.Constants = _parse_constants(reader, num_const)
    after_consts_pos = reader.pos

    num_sub = reader.g32()

    if num_sub > _MAX_SENSIBLE_SUBPROTOS and num_const > 0:

        saved_consts = list(chunk.Constants)
        saved_pos = reader.pos

        reader.pos = const_start_pos
        chunk.Constants = _parse_constants(reader, num_const - 1)
        new_after_consts_pos = reader.pos
        new_num_sub = reader.g32()

        if new_num_sub <= _MAX_SENSIBLE_SUBPROTOS:

            num_sub = new_num_sub
        else:

            chunk.Constants = saved_consts
            reader.pos = saved_pos
            num_sub = new_num_sub if new_num_sub <= _MAX_SENSIBLE_SUBPROTOS else 0

    if num_sub > _MAX_SENSIBLE_SUBPROTOS:
        num_sub = 0

    for i in range(num_sub):
        try:
            sub = parse_chunk(reader, chunk, i)
            chunk.Protos.append(sub)
        except Exception:

            break

    _resolve_refs(chunk)
    return chunk

def deserialize(data: bytes) -> Chunk:

    reader = BytecodeReader(data)
    try:
        chunk = parse_chunk(reader, None, 0)
    except Exception:
        chunk = Chunk()
    return chunk
