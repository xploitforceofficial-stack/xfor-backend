"""Correct splice: a ends with 'n[e[l' and b starts with '=E(e[t])' — the missing piece
is ']'. So v1 should be 'n[e[l]' + '=E...' = n[e[l]=E... no wait, n[e[l]]=E needs TWO
']'. a ends 'n[e[l' (one unclosed [), then we need ']]' before '='. v1 added only one.
Add a variant with ']]'."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
a = s[1000532:1005928]
b = s[1005930:]

variants = {
    'j1': a + ']' + b,
    'j2': a + ']]' + b,
}
for name, v in variants.items():
    out = 'for l,e in pairs({(function(e,...)' + v + '\nend)(({}),...)}) do return e end;'
    open('Samples/PSU/v5/_v5cand_%s.lua' % name, 'w', encoding='latin1').write(out)
    print(name, 'written')
