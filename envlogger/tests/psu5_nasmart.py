"""Smarter: walk the file, skip strings/comments properly, find the LAST position where
the top-level (depth 0) is still balanced, printing context there."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
BS = chr(92)

i, n = 0, len(s)
depth = 0
stack = []
last_balanced = 0
in_lstr = 0
line = 1

def skip_lstr(i, level):
    closer = ']' + '=' * (level - 1) + ']' if level else ']]'
    j = s.find(closer, i)
    return (j + len(closer)) if j >= 0 else n

while i < n:
    c = s[i]
    if c == '-' and s[i+1:i+2] == '-':
        if s[i+2:i+3] == '[':
            j = i + 2
            m = 0
            while j < n and s[j] == '[':
                m += 1; j += 1
                if m > 5: break
            level = m - 1
            if level >= 0 and (m >= 1):

                closer = ']' + '=' * (level - 1) + ']' if level else ']]'
                j2 = s.find(closer, j)
                if j2 >= 0:
                    i = j2 + len(closer)
                    continue
        while i < n and s[i] != '\n':
            i += 1
        continue
    if c == '[':
        j = i + 1
        m = 0
        while j < n and s[j] == '=':
            m += 1; j += 1
        if j < n and s[j] == '[':
            e = skip_lstr(j + 1, m)
            i = e
            continue
        depth += 1; stack.append(('[' , i)); i += 1
        continue
    if c in '({':
        depth += 1; stack.append((c, i)); i += 1
        continue
    if c in ')}':
        if stack: stack.pop(); depth -= 1
        if not stack:
            last_balanced = i
        i += 1
        continue
    if c == ']':
        if stack and stack[-1][0] == '[':
            stack.pop(); depth -= 1
            if not stack: last_balanced = i
        i += 1
        continue
    if c in '"\'':
        j = i + 1
        while j < n:
            if s[j] == BS: j += 2
            elif s[j] == c: break
            elif s[j] == '\n': break
            else: j += 1
        i = j + 1
        continue
    i += 1

print('last top-level balanced close at:', last_balanced)
print('context before:', repr(s[last_balanced-80:last_balanced+1]))
print('context after :', repr(s[last_balanced+1:last_balanced+120]))
print()
print('unclosed stack entries (first 10):')
for e in stack[:10]:
    print(' ', e[0], 'at', e[1], ':', repr(s[e[1]:e[1]+40]))
