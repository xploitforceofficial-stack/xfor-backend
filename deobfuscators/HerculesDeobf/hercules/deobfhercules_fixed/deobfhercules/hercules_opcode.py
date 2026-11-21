OPCODES = [

    ("MOVE",       "ABC"),
    ("LOADK",      "ABx"),
    ("LOADBOOL",   "ABC"),
    ("LOADNIL",    "ABC"),
    ("GETUPVAL",   "ABC"),
    ("GETGLOBAL",  "ABx"),
    ("GETTABLE",   "ABC"),
    ("SETGLOBAL",  "ABx"),
    ("SETUPVAL",   "ABC"),
    ("SETTABLE",   "ABC"),
    ("NEWTABLE",   "ABC"),
    ("SELF",       "ABC"),
    ("ADD",        "ABC"),
    ("SUB",        "ABC"),
    ("MUL",        "ABC"),
    ("DIV",        "ABC"),
    ("MOD",        "ABC"),
    ("POW",        "ABC"),
    ("UNM",        "ABC"),
    ("NOT",        "ABC"),
    ("LEN",        "ABC"),
    ("CONCAT",     "ABC"),
    ("JMP",        "AsBx"),
    ("EQ",         "ABC"),
    ("LT",         "ABC"),
    ("LE",         "ABC"),
    ("TEST",       "ABC"),
    ("TESTSET",    "ABC"),
    ("CALL",       "ABC"),
    ("TAILCALL",   "ABC"),
    ("RETURN",     "ABC"),
    ("FORLOOP",    "AsBx"),
    ("FORPREP",    "AsBx"),
    ("TFORLOOP",   "ABC"),
    ("SETLIST",    "ABC"),
    ("CLOSE",      "ABC"),
    ("CLOSURE",    "ABx"),
    ("VARARG",     "ABC"),
]

OPNAMES = [op[0] for op in OPCODES]
OP_TYPES = {op[0]: op[1] for op in OPCODES}
OP_NAME_BY_NUM = {i: op[0] for i, op in enumerate(OPCODES)}

BITRK = 1 << 8

def is_k(x: int) -> bool:

    return x >= BITRK

def indexk(x: int) -> int:

    return x - BITRK
