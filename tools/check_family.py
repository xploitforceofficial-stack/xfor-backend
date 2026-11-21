"""Report which isL/isF/isM pattern (if any) a recovered stage matches.

Mirrors the predicates in envlogger/src/core/sandbox.luau so a stage that the
sandbox will NOT re-run can be seen, instead of guessing from the output.

Usage: python tools/check_family.py <stage.lua> [...]
"""
import pathlib
import re
import sys

def is_l(text: str) -> str:
    if len(text) < 1000:
        return "too short"
    if "Ef=function" in text and re.search(r"while v do if I<=", text):
        return "legacy: Ef=function + while v do if I<="
    if re.search(r"(bd=function|xd=function)", text) and re.search(r"while \w+ do if \w+<=", text):
        return "legacy: bd/xd=function + while .. if ..<="
    if "return setmetatable" in text and "[47]=function" in text and "buffer.fromstring" in text:
        return "v15: setmetatable + [47]=function + buffer.fromstring"
    if "return setmetatable" in text and "buffer.readf64" in text:
        return "v15: setmetatable + buffer.readf64"
    if "until false" in text and re.search(r"repeat\s+\w+,\w+,\w+,\w+=\w+:\w+\(.*?\)", text):
        return "v14: step wrapper (repeat a,b,c,d=x:y(...) until false)"
    if re.search(r"while true do if \w+==", text) and re.search(r"elseif \w+==", text):
        return "v14: flat equality dispatch (while true do if X==/elseif X==)"
    for banner in ("Luraph Obfuscator", "Luraph decompression error",
                   "does your environment support load/loadstring?"):
        if banner in text:
            return "banner: " + banner
    has_dispatch = ("while true do if" in text or "repeat if" in text
                    or re.search(r"while (\w+) do if (\w+)<=", text))
    if has_dispatch:
        for feed in ("string.unpack", "buffer.readu8", "buffer.readu32", "string.byte"):
            if feed in text:
                for shell in ("return(function", "return({", "LPH@", "LPH#", "setfenv"):
                    if shell in text:
                        return "modern shell: dispatch + %s + %s" % (feed, shell)
                return "dispatch + %s but NO Luraph shell marker" % feed
    if "Luraph decompression" in text and "loadstring" in text:
        return "v14.6: compressed loader shell"
    return "NO MATCH -> the sandbox will not re-run this stage"

def main() -> int:
    for arg in sys.argv[1:]:
        p = pathlib.Path(arg)
        text = p.read_text(encoding="utf-8", errors="replace")
        print("%-28s %7d chars  %s" % (p.name[:27], len(text), is_l(text)))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
