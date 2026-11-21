import os

HERE = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(os.environ.get('TEMP', '/tmp'), 'pol_a.lua')
data = open(p, 'rb').read().decode('latin1')

best = None
i = 0
n = len(data)
while i < n:
    if data[i] == '"':
        j = i + 1
        while j < n:
            if data[j] == '\\':
                j += 2
                continue
            if data[j] == '"':
                break
            j += 1
        if j - i > 100000 and best is None:
            best = (i, j + 1)
        i = j + 1
    else:
        i += 1

print('blob span', best, 'len', best[1] - best[0])

code = data[:best[0]] + '"<BLOB>"' + data[best[1]:]
out = os.path.join(HERE, '_pol_code.lua')
with open(out, 'w', encoding='utf-8') as f:
    f.write(code)
blob = os.path.join(HERE, '_pol_blob.bin')
with open(blob, 'wb') as f:
    f.write(data[best[0] + 1:best[1] - 1].encode('latin1'))
print('wrote', out, len(code), 'and', blob)
print('--- 260 chars before blob ---')
print(repr(data[:best[0]][-260:]))
