"""The tail structure after the env table is actually:
    ...;})  ← first env close
    [(576707054)]=((1810)); ... re-injected junk entries (still INSIDE the table constructor? no)
    }),...])})do return e end;  ← glue
Since v4.5's glue is '}),...)})do return e end;' and v5 has extra junk + ']' inside,
the simplest correct assembly: cut everything between the FIRST '})' close after the
env entries and the final '}),...)' glue, replacing with '}),...)':
   v = a + ']]' + b
   keep: v[:dup_i+2]  +  '}),...)' + '})' + 'do return e end;'
Wait our synthesized wrapper is: pairs({(function(e,...) body end)(({ENV}),...)})
The body's own text ends with '(({' + env entries + '})' — the env table — then glue
'..., ...)' completes the CALL args, then '})' closes the table literal + call, then
'do return e end;'. Original glue '}),...])})' has junk ']' inside — real form is
'}),...)' + '})'. So rebuild: v[:dup_i+2] + ',...)' + '})' + 'do return e end;'
"""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
a = s[1000532:1005928]
b = s[1005930:]
v = a + ']]' + b

marker = '})[(576707054)]=((1810));'
i = v.find(marker)
v4 = v[:i+2] + ',...)' + '})' + 'do return e end;'
out = 'for l,e in pairs({(function(e,...)' + v4 + '\nend))}) do return e end;'
open('Samples/PSU/v5/_v5cand_j4.lua', 'w', encoding='latin1').write(out)
print('j4 written, len', len(out))
print('tail:', repr(v4[-120:]))
