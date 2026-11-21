"""Find the statement assigning v4's LZW result: search backwards for 'local' before the payload call."""
v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()

i = v4.find('"PSU|')

lb = v4.rfind('local', 0, i)
print("last 'local' before payload @", lb)
print("statement head:", repr(v4[lb:lb + 120]))

eq = v4.find('=', lb)
print("local names:", repr(v4[lb:eq]))
print()

en = v4.find(',(#R-G);') + len(',(#R-G);')
print("next statement after call:", repr(v4[en:en + 200]))
