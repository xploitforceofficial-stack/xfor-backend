import sys, math, collections

path = sys.argv[1] if len(sys.argv) > 1 else "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_pol_program.bin"
data = open(path, "rb").read()
print("len:", len(data))

counts = collections.Counter(data)
ent = -sum((c / len(data)) * math.log2(c / len(data)) for c in counts.values())
print(f"entropy: {ent:.3f} bits/byte")

print("top 12 bytes:", [(hex(b), n) for b, n in counts.most_common(12)])

runs = []
cur_start, cur_len = None, 0
for i, b in enumerate(data):
    if 32 <= b <= 126 or b in (9, 10, 13):
        if cur_start is None:
            cur_start = i
        cur_len += 1
    else:
        if cur_len >= 20:
            runs.append((cur_start, cur_len))
        cur_start, cur_len = None, 0
if cur_len >= 20:
    runs.append((cur_start, cur_len))
print(f"\nASCII runs >=20 chars: {len(runs)}")
for start, ln in runs[:60]:
    frag = data[start:start + min(ln, 110)]
    print(f"  @{start:6d} len={ln:5d}: {frag.decode('ascii', 'replace')!r}")
