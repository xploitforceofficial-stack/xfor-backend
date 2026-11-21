from __future__ import annotations
from typing import List, Tuple, Optional

class Token:
    __slots__ = ("kind", "value", "pos")

    def __init__(self, kind: str, value: str, pos: int):
        self.kind = kind
        self.value = value
        self.pos = pos

    def __repr__(self):
        return f"Token({self.kind!r}, {self.value!r})"

_BLOCK_CLOSE = {"end", "until", "elseif", "else"}

_BLOCK_OPEN_AFTER = {"function", "do", "repeat"}

_KEYWORDS_THEN = {"then"}
_KEYWORDS_ELSE = {"else", "elseif"}

def _is_ident_start(ch: str) -> bool:
    return ch.isalpha() or ch == "_"

def _is_ident_cont(ch: str) -> bool:
    return ch.isalnum() or ch == "_"

def _is_digit(ch: str) -> bool:
    return ch.isdigit()

def _read_string(src: str, i: int, quote: str) -> Tuple[str, int]:

    start = i
    i += 1
    n = len(src)
    while i < n:
        ch = src[i]
        if ch == "\\":

            i += 2
            continue
        if ch == quote:
            i += 1
            return src[start:i], i
        if ch == "\n":

            return src[start:i], i
        i += 1

    return src[start:i], i

def _read_long_string(src: str, i: int) -> Tuple[str, int]:

    start = i
    n = len(src)

    j = i + 1
    level = 0
    while j < n and src[j] == "=":
        level += 1
        j += 1
    if j >= n or src[j] != "[":

        return "[", i + 1

    i = j + 1

    close_pat = "]" + ("=" * level) + "]"
    while i < n:
        if src[i:i + len(close_pat)] == close_pat:
            i += len(close_pat)
            return src[start:i], i
        i += 1

    return src[start:i], i

def _read_comment(src: str, i: int) -> Tuple[str, int]:

    start = i
    n = len(src)

    if i + 2 < n and src[i + 2] == "[":

        body, next_i = _read_long_string(src, i + 2)
        if body.startswith("["):
            return src[i:next_i], next_i

    i += 2
    while i < n and src[i] != "\n":
        i += 1
    return src[start:i], i

def _read_number(src: str, i: int) -> Tuple[str, int]:

    start = i
    n = len(src)

    if src[i] == "0" and i + 1 < n and src[i + 1] in ("x", "X"):
        i += 2
        while i < n and (src[i] in "0123456789abcdefABCDEF_"):
            i += 1
        return src[start:i], i

    while i < n and (src[i].isdigit() or src[i] in "._"):
        i += 1

    if i < n and src[i] in ("e", "E"):
        i += 1
        if i < n and src[i] in ("+", "-"):
            i += 1
        while i < n and src[i].isdigit():
            i += 1
    return src[start:i], i

def _read_ident(src: str, i: int) -> Tuple[str, int]:

    start = i
    n = len(src)
    while i < n and _is_ident_cont(src[i]):
        i += 1
    return src[start:i], i

def _read_operator(src: str, i: int) -> Tuple[str, int]:

    n = len(src)

    if src[i:i+3] in ("...",):
        return src[i:i+3], i + 3

    two = src[i:i+2]
    if two in ("==", "~=", "<=", ">=", "..", "::", "->"):
        return two, i + 2

    return src[i], i + 1

def tokenize(src: str) -> List[Token]:

    tokens: List[Token] = []
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]

        if ch.isspace():
            i += 1
            continue

        if ch == "-" and i + 1 < n and src[i + 1] == "-":
            text, i = _read_comment(src, i)
            tokens.append(Token("comment", text, i))
            continue

        if ch == '"' or ch == "'":
            text, i = _read_string(src, i, ch)
            tokens.append(Token("string", text, i))
            continue

        if ch == "[" and i + 1 < n and src[i + 1] in ("[", "="):
            text, i = _read_long_string(src, i)
            tokens.append(Token("string", text, i))
            continue

        if _is_digit(ch):
            text, i = _read_number(src, i)
            tokens.append(Token("number", text, i))
            continue

        if _is_ident_start(ch):
            text, i = _read_ident(src, i)
            tokens.append(Token("ident", text, i))
            continue

        text, i = _read_operator(src, i)
        tokens.append(Token("op", text, i))
    tokens.append(Token("eof", "", i))
    return tokens

_LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for",
    "function", "goto", "if", "in", "local", "nil", "not", "or",
    "repeat", "return", "then", "true", "until", "while",
}

def _is_block_open_keyword(tok: Token) -> bool:

    return tok.value in ("function", "do", "repeat")

def _needs_space_between(prev: Token, cur: Token) -> bool:

    if prev.kind in ("string", "number", "ident", "comment"):
        if cur.kind in ("string", "number", "ident"):
            return True
        if cur.kind == "op" and cur.value not in ("(", ")", "]", "}", ",", ";", ":", ".",
                                                    "==", "~=", "<=", ">=", "..", "::"):
            return True
        if cur.kind == "op" and cur.value in ("=", "(", "[", "{"):

            if cur.value == "=":
                return True
            return False
        return False
    if prev.kind == "op":

        if prev.value in (",", ";", "..", "==", "~=", "<=", ">=", "=",
                          "+", "-", "*", "/", "//", "%", "^", "#", "&", "|", "~"):
            if cur.kind == "op" and cur.value in ("(", ")", "]", "}", "["):
                return False
            return True
        if prev.value == ":" or prev.value == ".":
            return False

        return False
    return False

def format_lua(src: str, indent: str = "    ") -> str:

    tokens = tokenize(src)
    out_lines: List[str] = []
    cur_line: List[str] = []
    depth = 0

    paren_depth = 0

    pending_newline_after_body_open = False

    last_keyword_was_if_for_while = False

    def flush_line():
        nonlocal cur_line
        if not cur_line:
            return

        parts: List[str] = []
        for idx, (text, needs_space) in enumerate(cur_line):
            if idx == 0:
                parts.append(text)
            else:
                if needs_space:
                    parts.append(" " + text)
                else:
                    parts.append(text)
        line = "".join(parts)
        out_lines.append(indent * depth + line)
        cur_line = []

    def emit_token(tok: Token):

        nonlocal cur_line
        if cur_line:

            prev_text, _ = cur_line[-1]

            prev_kind = _classify_text(prev_text)
            needs_space = _needs_space_between_tokens(prev_kind, prev_text, tok)
            cur_line.append((tok.value, needs_space))
        else:
            cur_line.append((tok.value, False))

    cur_line_parts: List[Tuple[str, bool]] = []

    def flush():
        nonlocal cur_line_parts
        if not cur_line_parts:
            return
        line_parts: List[str] = []
        for idx, (text, needs_space) in enumerate(cur_line_parts):
            if idx == 0:
                line_parts.append(text)
            else:
                if needs_space:
                    line_parts.append(" " + text)
                else:
                    line_parts.append(text)
        line = "".join(line_parts)

        stripped = line.rstrip()
        if stripped:
            out_lines.append(indent * depth + stripped)
        cur_line_parts = []

    def push(tok: Token, needs_space: bool):
        cur_line_parts.append((tok.value, needs_space))

    def cur_line_empty() -> bool:
        return not cur_line_parts

    def last_token_text() -> Optional[str]:
        if not cur_line_parts:
            return None
        return cur_line_parts[-1][0]

    prev_tok: Optional[Token] = None
    for tok in tokens:
        if tok.kind == "eof":
            break

        if tok.kind == "comment":
            flush()
            out_lines.append(indent * depth + tok.value)
            prev_tok = tok
            continue

        needs_space = False
        if prev_tok is not None and not cur_line_empty():
            needs_space = _needs_space_between_tokens(prev_tok.kind, prev_tok.value, tok)

        if tok.kind == "ident" and tok.value in ("end", "until", "elseif", "else"):

            flush()
            if tok.value in ("end", "until"):
                depth = max(0, depth - 1)

            push(tok, False)

            if tok.value == "end":

                pass
            prev_tok = tok
            continue

        if tok.kind == "ident" and tok.value in ("then", "do"):
            push(tok, needs_space)

            flush()
            depth += 1
            prev_tok = tok
            continue

        if tok.kind == "ident" and tok.value in ("function", "repeat"):
            push(tok, needs_space)

            prev_tok = tok
            continue

        if tok.kind == "op" and tok.value == ";":

            if cur_line_empty():
                continue
            push(tok, needs_space)
            flush()
            prev_tok = tok
            continue

        if tok.kind == "op" and tok.value in ("(", "[", "{"):
            paren_depth += 1
            push(tok, needs_space)
            prev_tok = tok
            continue
        if tok.kind == "op" and tok.value in (")", "]", "}"):
            paren_depth = max(0, paren_depth - 1)
            push(tok, needs_space)

            if tok.value == ")":

                _line_parts = []
                for _idx, (_text, _ns) in enumerate(cur_line_parts):
                    if _idx == 0:
                        _line_parts.append(_text)
                    else:
                        _line_parts.append((" " + _text) if _ns else _text)
                line_text = "".join(_line_parts)
                stripped = line_text.lstrip()

                if stripped.endswith(")"):

                    func_pos = stripped.find("function")
                    if func_pos >= 0:

                        before = stripped[:func_pos].rstrip()

                        is_header = (
                            before == ""
                            or before.endswith("local")
                            or before.endswith("(")
                            or before.endswith(",")
                            or before.endswith("=")
                            or before.endswith("return")
                            or before.endswith("do")
                            or before.endswith("then")
                            or before.endswith("else")
                            or before.endswith("(local")
                        )
                        if is_header:
                            flush()
                            depth += 1
            prev_tok = tok
            continue

        if tok.kind == "ident" and tok.value == "return":
            if not cur_line_empty():

                last_text = last_token_text()
                if last_text and (last_text[-1] in ")]}\"'" or last_text == "end"
                                  or _is_identifier(last_text)
                                  or _is_number(last_text)):
                    flush()
            push(tok, needs_space)
            prev_tok = tok
            continue

        if tok.kind == "ident" and tok.value in ("local", "if", "for", "while"):
            if not cur_line_empty():
                flush()
            push(tok, needs_space)
            prev_tok = tok
            continue

        push(tok, needs_space)
        prev_tok = tok

    flush()

    return "\n".join(out_lines) + "\n"

def _classify_text(text: str) -> str:

    if not text:
        return "op"
    if text[0] in ("'", '"', "["):

        if text.startswith("[") and (len(text) < 2 or text[1] in ("[", "=")):
            return "string"
        if text[0] in ("'", '"'):
            return "string"
    if text[0].isdigit():
        return "number"
    if text[0].isalpha() or text[0] == "_":
        return "ident"
    if text.startswith("--"):
        return "comment"
    return "op"

def _is_identifier(text: str) -> bool:
    if not text:
        return False
    if not (text[0].isalpha() or text[0] == "_"):
        return False
    return all(ch.isalnum() or ch == "_" for ch in text[1:])

def _is_number(text: str) -> bool:
    if not text:
        return False
    return text[0].isdigit()

def _needs_space_between_tokens(prev_kind: str, prev_text: str, cur: Token) -> bool:

    if prev_kind == "comment":
        return True

    if prev_kind == "string":
        if cur.kind == "op" and cur.value in (")", "]", "}", ",", ";", ":", ".",
                                                "..", "::"):
            return False
        if cur.kind == "op" and cur.value in ("==", "~=", "<=", ">=", "+", "-",
                                                "*", "/", "//", "%", "^", "&",
                                                "|", "~", "..", "=", "<", ">"):
            return True
        return True

    if prev_kind == "number":
        if cur.kind in ("ident", "string", "number"):
            return True
        if cur.kind == "op" and cur.value in (")", "]", "}", ",", ";", ".", ":"):
            return False
        if cur.kind == "op" and cur.value in ("(", "[", "{"):

            return False

        return True

    if prev_kind == "ident":

        if prev_text in ("and", "or", "not", "in", "return", "then", "do",
                         "else", "elseif", "while", "if", "for", "local",
                         "function", "repeat", "break", "goto"):
            if cur.kind == "op" and cur.value in (";", ",", ")", "]", "}"):
                return False
            return True

        if prev_text in ("end", "until"):
            if cur.kind == "op" and cur.value in (")", "]", "}", ",", ";", ".", ":"):
                return False

            return True
        if cur.kind in ("ident", "string", "number"):
            return True
        if cur.kind == "op":

            if cur.value in ("(", "[", "{", ")", "]", "}", ",", ";", ":", "."):
                return False
            if cur.value == "..":

                return True

            return True
        return False

    if prev_kind == "op":

        if prev_text in (",", ";"):
            return True
        if prev_text in (".", ":", "(", "[", "{"):

            if cur.kind == "op" and cur.value in ("(", "[", "{", ".", ":", ")", "]", "}", ",", ";"):
                return False
            if cur.kind == "string":
                return False
            return False
        if prev_text in (")", "]", "}"):

            if cur.kind == "op" and cur.value in ("(", "[", "{", ".", ":", ")", "]", "}", ",", ";"):
                return False
            if cur.kind == "op" and cur.value == "..":
                return True
            if cur.kind == "string":
                return False

            return True
        if prev_text in ("=", "==", "~=", "<=", ">=", "+", "-", "*", "/", "//",
                         "%", "^", "&", "|", "~", "..", "<", ">", "#"):

            if cur.kind == "op" and cur.value in (")", "]", "}", ",", ";"):
                return False

            if prev_text == "#" and cur.kind in ("ident", "string"):
                return False
            return True
        return False
    return False
