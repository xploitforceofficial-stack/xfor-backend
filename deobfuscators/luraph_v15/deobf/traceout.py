"""
Behaviour trace output, shared by every obfuscator plugin: the rendered
trace of a harness run (envlog.luau) -> readable Luau (tidy.py, fold.py,
spacing.py).
"""
import os
import re
import sys

def stmt_count(body):
    m = re.search(r"-- (\d+) statements recorded", body)
    return int(m.group(1)) if m else 0

def take_line(body, name):
    """(value of the first `\\0NAME value` line, body without it); value is None if absent."""
    m = re.search(r"\x00%s ([^\n]*)\n" % name, body)
    if not m:
        return None, body
    return m.group(1), body[:m.start()] + body[m.end():]

def take_strings(body):
    """(body, the strings section of `dump_strings` or None)."""
    if "\x00ENVLOG-STRINGS" in body:
        body, strings = body.split("\x00ENVLOG-STRINGS\n", 1)
        return body, strings
    return body, None

def header(input_path, notes=()):
    h = ("-- omnidbf reconstruction (observed behaviour)\n"
         "-- source: %s\n"
         "-- NOTE: rebuilt from what the script actually did at runtime, so any\n"
         "--       branch it never took is absent and the conditions it branched\n"
         "--       on are only recorded as comments.\n"
         % os.path.basename(input_path))
    return h + "".join("-- %s\n" % n for n in notes)

def render(text, args, preamble=True):
    """The readable trace: tidy (+ fold) + spacing, or only the fold markers
    stripped with --no-tidy. preamble: strip Luraph-style environment probes
    at the top (tidy.strip_preamble)."""
    if os.environ.get("DEOB_PRETIDY"):

        with open(os.environ["DEOB_PRETIDY"], "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    if not args.no_tidy:
        import tidy
        import spacing
        t = tidy.tidy(text, preamble=preamble and not args.keep_preamble, fold_code=not args.no_fold)
        return strip_comments(spacing.space(t))
    import fold
    return strip_comments(fold.strip_markers(text))

def status_line(body):
    status = body.splitlines()[0] if body else ""
    print("[*] " + status.lstrip("- "), file=sys.stderr)

CREDIT = re.compile(r"^--\s*(Deobfuscated by|Detected obfuscation:)")

_LONG_OPEN = re.compile(r"\[(=*)\[")

def strip_comments(text):
    """`text` without its `--` comments, so the delivered file is code only.

    A trace is mostly comments: the banner, the run status, the fold markers
    (`--@12 3:inv,...`), and the condition notes on every branch. They are
    working state for the passes that run before this point, not part of the
    reconstruction, so the last step drops them.

    Written as a scanner rather than a line filter because `--` inside a string
    is not a comment, and traces are full of strings that contain it (URLs,
    long `[==[...]==]` payloads, the quoted text of a loadstring'd chunk). Only
    a `--` reached outside any string starts a comment.

    The credit header survives; blank-line runs left behind collapse to one, so
    the result reads as code rather than as gaps.
    """
    out = []
    i, n = 0, len(text)
    blank_line = True
    header_zone = True
    while i < n:
        c = text[i]
        if c == "\n":
            out.append("\n")
            i += 1
            blank_line = True
            continue
        if c in " \t\r":
            out.append(c)
            i += 1
            continue

        if c == "[" and not (i + 1 < n and text[i + 1] == "-"):
            m = _LONG_OPEN.match(text, i)
            if m:
                close = "]" + m.group(1) + "]"
                j = text.find(close, i + m.end())
                j = n if j < 0 else j + len(close)
                out.append(text[i:j])
                i = j
                blank_line = False
                continue
        if c in "\"'`":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:min(j + 1, n)])
            i = j + 1
            blank_line = False
            continue
        if text.startswith("--", i):
            j0 = i
            m = re.match(r"--\[(=*)\[", text[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = text.find(close, i + m.end())
                i = n if j < 0 else j + len(close)

                if blank_line and i < n and text[i] == "\n":
                    i += 1
                continue
            j = text.find("\n", i)
            i = n if j < 0 else j

            if header_zone and CREDIT.match(text[j0:i]):
                out.append(text[j0:i])
                if i < n:
                    out.append("\n")
                    i += 1
                continue

            if blank_line and i < n:
                i += 1
            continue
        out.append(c)
        i += 1
        if c.strip():
            header_zone = False
        blank_line = False

    kept, dropped = [], False
    for ln in "".join(out).split("\n"):
        if ln.strip():
            dropped = False
            kept.append(ln.rstrip())
        elif not dropped:
            kept.append("")
            dropped = True
    return "\n".join(kept).strip("\n") + "\n"
