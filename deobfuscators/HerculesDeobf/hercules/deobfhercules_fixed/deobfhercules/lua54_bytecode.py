from __future__ import annotations
import struct
from dataclasses import dataclass, field
from typing import List, Any, Optional

from .deserializer import Chunk, Instruction

OP_MOVE        = 0
OP_LOADI       = 1
OP_LOADF       = 2
OP_LOADK       = 3
OP_LOADKX      = 4
OP_LOADFALSE   = 5
OP_LFALSESKIP  = 6
OP_LOADTRUE    = 7
OP_LOADNIL     = 8
OP_GETUPVAL    = 9
OP_SETUPVAL    = 10
OP_GETTABUP    = 11
OP_GETTABLE    = 12
OP_GETI        = 13
OP_GETFIELD    = 14
OP_SETTABUP    = 15
OP_SETTABLE    = 16
OP_SETI        = 17
OP_SETFIELD    = 18
OP_NEWTABLE    = 19
OP_SELF        = 20
OP_ADDI        = 21
OP_ADDK        = 22
OP_SUBK        = 23
OP_MULK        = 24
OP_MODK        = 25
OP_POWK        = 26
OP_DIVK        = 27
OP_IDIVK       = 28
OP_BANDK       = 29
OP_BORK        = 30
OP_BXORK       = 31
OP_SHRI        = 32
OP_SHLI        = 33
OP_ADD         = 34
OP_SUB         = 35
OP_MUL         = 36
OP_MOD         = 37
OP_POW         = 38
OP_DIV         = 39
OP_IDIV        = 40
OP_BAND        = 41
OP_BOR         = 42
OP_BXOR        = 43
OP_SHL         = 44
OP_SHR         = 45
OP_MMBIN       = 46
OP_MMBINI      = 47
OP_MMBINK      = 48
OP_UNM         = 49
OP_BNOT        = 50
OP_NOT         = 51
OP_LEN         = 52
OP_CONCAT      = 53
OP_CLOSE       = 54
OP_TBC         = 55
OP_JMP         = 56
OP_EQ          = 57
OP_LT          = 58
OP_LE          = 59
OP_EQK         = 60
OP_EQI         = 61
OP_LTI         = 62
OP_LEI         = 63
OP_GTI         = 64
OP_GEI         = 65
OP_TEST        = 66
OP_TESTSET     = 67
OP_CALL        = 68
OP_TAILCALL    = 69
OP_RETURN      = 70
OP_RETURN0     = 71
OP_RETURN1     = 72
OP_FORLOOP     = 73
OP_FORPREP     = 74
OP_TFORPREP    = 75
OP_TFORCALL    = 76
OP_TFORLOOP    = 77
OP_SETLIST     = 78
OP_CLOSURE     = 79
OP_VARARG      = 80
OP_VARARGPREP  = 81
OP_EXTRAARG    = 82

OPCODES_54 = [
    ("MOVE",       "iABC"),
    ("LOADI",      "iAsBx"),
    ("LOADF",      "iAsBx"),
    ("LOADK",      "iABx"),
    ("LOADKX",     "iABx"),
    ("LOADFALSE",  "iABC"),
    ("LFALSESKIP", "iABC"),
    ("LOADTRUE",   "iABC"),
    ("LOADNIL",    "iABC"),
    ("GETUPVAL",   "iABC"),
    ("SETUPVAL",   "iABC"),
    ("GETTABUP",   "iABC"),
    ("GETTABLE",   "iABC"),
    ("GETI",       "iABC"),
    ("GETFIELD",   "iABC"),
    ("SETTABUP",   "iABC"),
    ("SETTABLE",   "iABC"),
    ("SETI",       "iABC"),
    ("SETFIELD",   "iABC"),
    ("NEWTABLE",   "iABC"),
    ("SELF",       "iABC"),
    ("ADDI",       "iABC"),
    ("ADDK",       "iABC"),
    ("SUBK",       "iABC"),
    ("MULK",       "iABC"),
    ("MODK",       "iABC"),
    ("POWK",       "iABC"),
    ("DIVK",       "iABC"),
    ("IDIVK",      "iABC"),
    ("BANDK",      "iABC"),
    ("BORK",       "iABC"),
    ("BXORK",      "iABC"),
    ("SHRI",       "iABC"),
    ("SHLI",       "iABC"),
    ("ADD",        "iABC"),
    ("SUB",        "iABC"),
    ("MUL",        "iABC"),
    ("MOD",        "iABC"),
    ("POW",        "iABC"),
    ("DIV",        "iABC"),
    ("IDIV",       "iABC"),
    ("BAND",       "iABC"),
    ("BOR",        "iABC"),
    ("BXOR",       "iABC"),
    ("SHL",        "iABC"),
    ("SHR",        "iABC"),
    ("MMBIN",      "iABC"),
    ("MMBINI",     "iABC"),
    ("MMBINK",     "iABC"),
    ("UNM",        "iABC"),
    ("BNOT",       "iABC"),
    ("NOT",        "iABC"),
    ("LEN",        "iABC"),
    ("CONCAT",     "iABC"),
    ("CLOSE",      "iABC"),
    ("TBC",        "iABC"),
    ("JMP",        "isJ"),
    ("EQ",         "iABC"),
    ("LT",         "iABC"),
    ("LE",         "iABC"),
    ("EQK",        "iABC"),
    ("EQI",        "iABC"),
    ("LTI",        "iABC"),
    ("LEI",        "iABC"),
    ("GTI",        "iABC"),
    ("GEI",        "iABC"),
    ("TEST",       "iABC"),
    ("TESTSET",    "iABC"),
    ("CALL",       "iABC"),
    ("TAILCALL",   "iABC"),
    ("RETURN",     "iABC"),
    ("RETURN0",    "iABC"),
    ("RETURN1",    "iABC"),
    ("FORLOOP",    "iABx"),
    ("FORPREP",    "iABx"),
    ("TFORPREP",   "iABx"),
    ("TFORCALL",   "iABC"),
    ("TFORLOOP",   "iABx"),
    ("SETLIST",    "iABC"),
    ("CLOSURE",    "iABx"),
    ("VARARG",     "iABC"),
    ("VARARGPREP", "iABC"),
    ("EXTRAARG",   "iAx"),
]

OP_NAME_BY_NUM_54 = {i: name for i, (name, _) in enumerate(OPCODES_54)}
OP_MODE_BY_NUM_54 = {i: mode for i, (_, mode) in enumerate(OPCODES_54)}

MAXARG_sBx = 65535
MAXARG_Bx  = 131071
MAXARG_Ax  = (1 << 26) - 1
MAXARG_sJ  = (1 << 19) - 1
OFFSET_sJ  = MAXARG_sJ

LUA_VNIL    = 0x00
LUA_VFALSE  = 0x01
LUA_VTRUE   = 0x11
LUA_VNUMINT = 0x03
LUA_VNUMFLT = 0x13
LUA_VSHRSTR = 0x04
LUA_VLNGSTR = 0x14

class Lua54Reader:
    def __init__(self, data: bytes, pos: int = 0):
        self.data = data
        self.pos = pos

    def eof(self) -> bool:
        return self.pos >= len(self.data)

    def u8(self) -> int:
        v = self.data[self.pos]
        self.pos += 1
        return v

    def u16(self) -> int:
        v1, v2 = self.data[self.pos], self.data[self.pos + 1]
        self.pos += 2
        return v1 | (v2 << 8)

    def u32(self) -> int:
        v1, v2, v3, v4 = (
            self.data[self.pos],
            self.data[self.pos + 1],
            self.data[self.pos + 2],
            self.data[self.pos + 3],
        )
        self.pos += 4
        return v1 | (v2 << 8) | (v3 << 16) | (v4 << 24)

    def i64(self) -> int:
        v = struct.unpack_from("<q", self.data, self.pos)[0]
        self.pos += 8
        return v

    def f64(self) -> float:
        v = struct.unpack_from("<d", self.data, self.pos)[0]
        self.pos += 8
        return v

    def size_t(self) -> int:

        x = 0
        while True:
            b = self.u8()
            x = (x << 7) | (b & 0x7F)
            if (b & 0x80) != 0:
                break
            if x > (1 << 56):
                raise ValueError("size_t overflow (corrupt dump?)")
        return x

    def string(self) -> Optional[str]:
        n = self.size_t()
        if n == 0:
            return None

        length = n - 1
        raw = self.data[self.pos : self.pos + length]
        self.pos += length
        try:
            return raw.decode("utf-8", errors="replace")
        except Exception:
            return raw.decode("latin-1", errors="replace")

LUAC_SIGNATURE = b"\x1bLua"
LUAC_VERSION_54 = 0x54
LUAC_DATA = b"\x19\x93\r\n\x1a\n"
LUAC_INT = 0x5678
LUAC_NUM = 370.5

def looks_like_lua54_bytecode(data: bytes) -> bool:

    if len(data) < 13:
        return False
    if data[:4] != LUAC_SIGNATURE:
        return False
    if data[4] != LUAC_VERSION_54:
        return False

    if data[6:12] != LUAC_DATA:
        return False
    return True

def parse_header(r: Lua54Reader) -> dict:

    sig = bytes(r.data[r.pos : r.pos + 4]); r.pos += 4
    if sig != LUAC_SIGNATURE:
        raise ValueError(f"Bad Lua signature: {sig!r}")
    version = r.u8()
    if version != LUAC_VERSION_54:
        raise ValueError(f"Unsupported Lua version: 0x{version:02x} (only 5.4 supported)")
    fmt = r.u8()
    if fmt != 0:
        raise ValueError(f"Unknown Lua dump format: {fmt}")
    data_check = bytes(r.data[r.pos : r.pos + 6]); r.pos += 6
    if data_check != LUAC_DATA:
        raise ValueError("LUAC_DATA mismatch")
    sizeof_inst = r.u8()
    sizeof_int  = r.u8()
    sizeof_num  = r.u8()
    if sizeof_inst != 4:
        raise ValueError(f"sizeof(Instruction)={sizeof_inst}, expected 4")
    if sizeof_int != 8:
        raise ValueError(f"sizeof(lua_Integer)={sizeof_int}, expected 8")
    if sizeof_num != 8:
        raise ValueError(f"sizeof(lua_Number)={sizeof_num}, expected 8")
    luac_int = r.i64()
    if luac_int != LUAC_INT:
        raise ValueError(f"LUAC_INT mismatch: got {luac_int}, expected {LUAC_INT}")
    luac_num = r.f64()
    if luac_num != LUAC_NUM:
        raise ValueError(f"LUAC_NUM mismatch: got {luac_num}, expected {LUAC_NUM}")
    return {
        "version": version,
        "format": fmt,
        "sizeof_inst": sizeof_inst,
        "sizeof_int": sizeof_int,
        "sizeof_num": sizeof_num,
    }

def parse_constant(r: Lua54Reader) -> Any:
    t = r.u8()
    if t == LUA_VNIL:
        return None
    if t == LUA_VFALSE:
        return False
    if t == LUA_VTRUE:
        return True
    if t == LUA_VNUMINT:
        return r.i64()
    if t == LUA_VNUMFLT:
        return r.f64()
    if t in (LUA_VSHRSTR, LUA_VLNGSTR):
        return r.string()
    raise ValueError(f"Unknown constant type byte: 0x{t:02x}")

_POS_OP = 0
_POS_A  = 7
_POS_k  = 15
_POS_B  = 16
_POS_C  = 24
_POS_Bx = 15
_POS_Ax = 7
_POS_sJ = 7

_SIZE_OP = 7
_SIZE_A  = 8
_SIZE_k  = 1
_SIZE_B  = 8
_SIZE_C  = 8
_SIZE_Bx = 17
_SIZE_Ax = 25
_SIZE_sJ = 26

_SIZE_sJ = 25

_MASK = (1 << _SIZE_OP) - 1

def _getarg(raw: int, pos: int, size: int) -> int:
    return (raw >> pos) & ((1 << size) - 1)

def decode_instruction(raw: int) -> Instruction:

    opcode = raw & 0x7F
    A = (raw >> 7) & 0xFF
    k_flag = (raw >> 15) & 0x1
    B = (raw >> 16) & 0xFF
    C = (raw >> 24) & 0x7F
    Bx = (raw >> 15) & 0x1FFFF
    sBx = Bx - (0x1FFFF >> 1)
    Ax = (raw >> 7) & 0x1FFFFFF
    sJ = Ax - (0x1FFFFFF >> 1)

    mode = OP_MODE_BY_NUM_54.get(opcode, "iABC")
    if mode == "isJ":
        return Instruction(
            S=opcode, A=A, B=B, C=C, Bx=Bx, sBx=sBx,
            f=sJ,
        )
    return Instruction(
        S=opcode,
        A=A,
        B=B,
        C=C,
        Bx=Bx,
        sBx=sBx,

        f=sBx if mode == "iAsBx" else None,
    )

def parse_proto(r: Lua54Reader, parent: Optional[Chunk], idx: int) -> Chunk:

    source = r.string()
    linedefined = r.size_t()
    lastlinedefined = r.size_t()
    numparams = r.u8()
    is_vararg = r.u8()
    maxstack = r.u8()

    chunk = Chunk(
        Upvals=0,
        Parameters=numparams,
        MaxStack=maxstack,
        Parent=parent,
        Index=idx,
    )

    chunk.linedefined = linedefined
    chunk.lastlinedefined = lastlinedefined
    chunk.is_vararg = bool(is_vararg)
    chunk.source = source

    n_inst = r.size_t()
    chunk.Instructions = [decode_instruction(r.u32()) for _ in range(n_inst)]

    n_const = r.size_t()
    chunk.Constants = [parse_constant(r) for _ in range(n_const)]

    n_up = r.size_t()
    chunk.Upvals = n_up
    chunk.UpvalueDescs = []
    for _ in range(n_up):
        instack = r.u8()
        idx_ = r.u8()
        kind = r.u8()
        chunk.UpvalueDescs.append({"instack": instack, "kind": kind, "idx": idx_, "name": None})

    n_sub = r.size_t()
    for i in range(n_sub):
        sub = parse_proto(r, chunk, i)
        chunk.Protos.append(sub)

    sizelineinfo = r.size_t()
    r.pos += sizelineinfo

    sizeabslineinfo = r.size_t()
    for _ in range(sizeabslineinfo):
        r.size_t()
        r.size_t()

    sizelocvars = r.size_t()
    for _ in range(sizelocvars):
        r.string()
        r.size_t()
        r.size_t()

    sizeupvalnames = r.size_t()
    for _ in range(sizeupvalnames):
        r.string()

    return chunk

def parse(data: bytes) -> Chunk:

    r = Lua54Reader(data, 0)
    parse_header(r)

    closure_nup = r.u8()
    main = parse_proto(r, None, 0)

    return main
