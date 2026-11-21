"""Find unclosed string literals in the extracted PSU v5 env table."""
s = open('Samples/PSU/v5/_envtable1.lua', encoding='utf-8', errors='replace').read()
print("len:", len(s))
BS = chr(92)
i = 0
n = len(s)
count = 0
while i < n:
    c = s[i]
    if c == '"' or c == "'":
        q = c
        j = i + 1
        closed = False
        while j < n:
            if s[j] == BS:
                j += 2
                continue
            if s[j] == q:
                closed = True
                j += 1
                break
            if s[j] == '\n':
                break
            j += 1
        if not closed:
            count += 1
            print("UNCLOSED string at", i, ":", repr(s[max(0, i - 70):i + 90]))
            if count > 5:
                break
            i = j
            continue
        i = j
    else:
        i += 1
print("done, unclosed:", count)
