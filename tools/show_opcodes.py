"""Print the extracted leaves for the opcodes that actually run, hottest first."""
import collections
import pathlib
import sys

WORK = pathlib.Path(__file__).resolve().parent / "work"

def main() -> int:
    counts = collections.Counter(
        int(line.split("\t")[1])
        for line in (WORK / "op.tsv").read_text(encoding="utf-8").splitlines()
    )
    top = [int(x) for x in sys.argv[1:]] if len(sys.argv) > 1 else [
        p for p, _ in counts.most_common(12)
    ]
    for P in top:
        f = WORK / "opcodes" / f"{P:03d}.lua"
        text = f.read_text(encoding="utf-8") if f.exists() else "-- missing"
        print("=" * 60)
        print(f"opcode {P}   executed {counts.get(P, 0):,}x")
        print(text.rstrip())
        print()
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
