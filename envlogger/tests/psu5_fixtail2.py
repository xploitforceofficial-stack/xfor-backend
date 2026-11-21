"""The glue '}),...)})do return e end;' got cut by the j3 splice — my rfind ran on the
wrong substring because the glue contains '})' twice. Redo: search for 'do return e end;'
and keep everything from '})' at dup-closer through glue properly."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
a = s[1000532:1005928]
b = s[1005930:]
v = a + ']]' + b

endmark = 'do return e end;'
g = v.rfind(endmark)
print('endmark at', g, 'len v', len(v))
print('tail from 23400:', repr(v[23400:]))

marker = '})[(576707054)]=((1810));'
i = v.find(marker)
print('dup at', i)

j = b.find(marker)
print('dup in b at', j, 'b tail from dup:', repr(b[j:j+400]))
