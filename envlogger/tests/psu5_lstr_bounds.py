"""Find the real long-string boundaries in PSU v5 1.lua and verify overall Lua structure."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()

i = s.find('[[')
print('long-string open at', i)
j = s.find(']]', i + 2)
k = s.find(']=]', i + 2)
print('first ]] at', j)
print('first ]=] at', k)

print()
print('around open:', repr(s[i-40:i+40]))
print()
print('around close:', repr(s[j-40:j+60]))
