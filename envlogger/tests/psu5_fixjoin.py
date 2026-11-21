"""The splice point 'n[e[l' + '=E(e[t])' should be 'n[e[l]]=E(e[t])' — the ]] got eaten
as the string close but the expression needs one more ']'. Test: body = s[1000532:] but
insert the missing ']' at the join."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()

a = s[1000532:1005928]
b = s[1005930:]
print('a tail:', repr(a[-20:]))
print('b head:', repr(b[:20]))

v1 = a + ']' + b

v2 = a + b

v3 = a[:-1] + b

for name, v in [('v1 +]', v1), ('v2 raw', v2), ('v3 cut', v3)]:
    out = 'for l,e in pairs({(function(e,...)' + v + '\nend)(({}),...)}) do return e end;'
    open('Samples/PSU/v5/_v5cand_%s.lua' % name, 'w', encoding='latin1').write(out)
    print(name, 'written')
