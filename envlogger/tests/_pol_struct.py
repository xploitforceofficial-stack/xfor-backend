import sys, os
p = os.path.join(os.environ.get('TEMP', '/tmp'), 'pol_a.lua')
data = open(p, 'rb').read().decode('latin1')
print('total', len(data))
print('num lines', data.count('\n'))

out = []
i = 0
n = len(data)
while i < n:
    ch = data[i]
    if ch == '"':
        j = i + 1
        buf = []
        while j < n:
            c = data[j]
            if c == '\\':
                buf.append(data[j:j+2]); j += 2; continue
            if c == '"':
                break
            buf.append(c); j += 1
        s = ''.join(buf)
        if len(s) > 500:
            out.append((len(s), i, s[:50]))
        i = j + 1
    else:
        i += 1

out.sort(reverse=True)
for L, at, head in out[:10]:
    print(L, 'at', at, repr(head))

print('--- tail ---')
print(repr(data[-300:]))
