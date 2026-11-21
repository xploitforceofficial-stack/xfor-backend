"""Log the v14 stage's key-derivation check, so a wrong environment shows up.

The v14 stage computes a value F from environment-derived inputs and hands it to
`Z6`, which is where a bad key is rejected. Nothing reports either, so a wrong
environment is indistinguishable from a payload that ran. This writes a patched
stage (the original with prints around that check) plus the
`LENGTH<TAB>PATH` manifest `main.luau --stage-patch` expects.

Usage:
  python tools/log_keycheck.py tools/stg4/stage.lua
  -> prints the manifest line to pass to deob/runLuraph
"""
import pathlib
import re
import sys

NEEDLE = re.compile(
    r"if not l\[(?P<slot>\d+)\]then F=\(81\+\(Y\.WJ\(",
)

def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src = pathlib.Path(sys.argv[1])
    text = src.read_text(encoding="utf-8", errors="replace")
    m = NEEDLE.search(text)
    if not m:
        print("no key check found in %s" % src)
        return 3
    start = m.start()

    end = text.find(";", text.find("(F)", start))
    if end < 0:
        print("could not find the end of the key assignment")
        return 3
    block = text[start:end + 1]

    slot = m.group("slot")
    fields = ("8167", "10980", "15537", "23128", "29017", "30459")

    probe = (
        "local _k1 = Y.jJ(l[8167])\n"
        "local _k2 = Y.yY(_k1, l[10980])\n"
        "local _k3 = (_k2 <= l[29017])\n"
        "local _k4 = _k3 and l[30459] or Y.W[9]\n"
        "local _k5 = _k4 - l[23128]\n"
        "local _k6 = Y.gY(_k5)\n"
        "local _k7 = Y.WJ(_k6, l[15537])\n"
    )
    parts = ['"[keycheck] slot=%s"' % slot]
    for k in fields:
        parts.append('.. " l[%s]=" .. tostring(l[%s])' % (k, k))
    parts.append('.. " W9=" .. tostring(Y.W[9])')
    for i in range(1, 8):
        parts.append('.. " _k%d=" .. tostring(_k%d)' % (i, i))
    parts.append('.. " F=" .. tostring(F)')
    log = (probe + block + "\nerror(" + "".join(parts) + ", 0)")
    patched = text[:start] + log + text[end + 1:]

    out = src.with_name(src.stem + "_keycheck.lua")
    out.write_text(patched, encoding="utf-8")
    manifest = src.with_name(src.stem + "_manifest.tsv")

    manifest.write_text("%d\t%s\n" % (len(text.encode("utf-8")), out.resolve().as_posix()),
                        encoding="utf-8")
    print("patched  :", out)
    print("manifest :", manifest)
    print("manifest line:", manifest.read_text(encoding="utf-8").strip())
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
