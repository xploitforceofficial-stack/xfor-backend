"""Tokenize the v5 file and print the top-level structure (outside strings/comments)."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
BS = chr(92)

i = 0
n = len(s)
tokens = []
line = 1
while i < n and len(tokens) < 80:
    c = s[i]
    if c == '\n':
        line += 1
        i += 1
    elif c in ' \t\r':
        i += 1
    elif c == '-' and s[i+1:i+2] == '-':

        if s[i+2:i+4] == '[[' or (s[i+2:i+3] == '[' and s[i+3:i+4] == '='):
            j = i + 2
            m = 0
            while j < n and s[j] == '[':
                j += 1
                m += 1
                if m > 5: break
            level = m - 1
            closer = ']' + '=' * (level - 1) + ']' if level else ']]'
            j = s.find(closer, j)
            i = (j + len(closer)) if j >= 0 else n
        else:
            while i < n and s[i] != '\n':
                i += 1
    elif c == '[' and s[i+1:i+2] == '[' or (c == '[' and s[i+1:i+2] == '='):

        j = i
        m = 0
        while j < n and s[j] == '[':
            j += 1
            m += 1
            if m > 5: break
        level = m - 1
        if level == 0 and s[i+1:i+2] != '[':
            tokens.append(('LSTR?', i, line)); i += 1; continue
        closer = ']' + '=' * (level - 1) + ']' if level else ']]'
        j = s.find(closer, j)
        tokens.append(('LSTR' + '=' * level, i, s[i:j].count('\n')))
        i = (j + len(closer)) if j >= 0 else n
    elif c in '"\'':
        q = c
        j = i + 1
        while j < n:
            if s[j] == BS:
                j += 2
            elif s[j] == q:
                break
            elif s[j] == '\n':
                break
            else:
                j += 1
        tokens.append(('STR', i, j - i))
        i = j + 1
    else:
        j = i
        while j < n and (s[j].isalnum() or s[j] == '_'):
            j += 1
        if j > i:
            tokens.append(('NAME' if s[i].isalpha() or s[i] == '_' else 'NUM', i, s[i:j]))
            i = j
        else:
            tokens.append(('OP', i, c))
            i += 1

for t in tokens:
    print(t)
