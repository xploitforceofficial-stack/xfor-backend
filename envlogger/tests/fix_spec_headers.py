"""Several *.spec.luau files lost the `--[[` that opens their header block,
leaving the prose as bare Lua and making Lune refuse to load them.
Re-insert the opener where the closer exists but the opener is gone."""
import glob
import re

fixed = []
for path in sorted(glob.glob("tests/*.spec.luau")):
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    lines = text.split("\n")
    closer = None
    for index, line in enumerate(lines[:40]):
        if line.strip() == "]]":
            closer = index
            break
    if closer is None:
        continue
    opener = None
    for index in range(closer - 1, -1, -1):
        if lines[index].strip().startswith("--[["):
            opener = index
            break
        if lines[index].strip().startswith("--!"):
            break
    if opener is not None:
        continue

    start = None
    for index in range(1, closer):
        stripped = lines[index].strip()
        if stripped == "" or stripped.startswith("--"):
            continue
        start = index
        break
    if start is None:
        continue
    lines.insert(start, "--[[")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
    fixed.append(path)

print("repaired:", ", ".join(fixed) if fixed else "none")
