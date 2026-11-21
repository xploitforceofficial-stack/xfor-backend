"""j2's only remaining error: the duplicated env-table closer
   ...;})[(576707054)]=((1810));[...];} then }),...)})do return e end
The tail has the table close '})' followed by junk re-assignments then another '}'.
Real structure (v4.5): ...;}),...)}) do return e end
Fix: collapse '})[' ... last '];}' before the final glue into just '})'."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
a = s[1000532:1005928]
b = s[1005930:]
v = a + ']]' + b

marker = '})[(576707054)]=((1810));'
i = v.find(marker)
print('dup closer at', i)
if i >= 0:

    glue = '}),...)})do return e end;'
    g = v.rfind(glue)
    print('glue at', g)

    v2 = v[:i+2] + v[g:]
    print('cut len:', g - (i+2))
    print('new tail:', repr(v2[-160:]))
    out = 'for l,e in pairs({(function(e,...)' + v2 + '\nend)(({}),...)}) do return e end;'
    open('Samples/PSU/v5/_v5cand_j3.lua', 'w', encoding='latin1').write(out)
    print('written j3, len', len(out))
