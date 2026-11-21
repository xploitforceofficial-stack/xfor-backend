"""Locate the env table open. The call-site text we saw was:
   'end;return A(I(),{},v())(...);end)(({[((#{117;109;}+289639432))=...' (from the j2 tail)
But that was in the OLD recon. In v = a+']]' + b (new splice), find 'end)(({'."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
a = s[1000532:1005928]
b = s[1005930:]
v = a + ']]' + b

for key in ['end)(({', 'v())(...);end;', 'return A(I(),{},v())']:
    i = v.find(key)
    print(repr(key), '->', i)

i = v.find('end;return A(I(),{},v())')
print('A-call at', i)
if i >= 0:
    print(repr(v[i:i+120]))
