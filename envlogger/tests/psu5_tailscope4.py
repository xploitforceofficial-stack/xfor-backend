"""The ]] split mid-expression: '=E(e[t]);' is a continuation. So the long string sits
INSIDE an expression like  f(...)<string>..E(e[t])...  Test cut points: the tail must
start right after a ';' at statement level. Find candidate starts in tail[:60] by
looking for where a full statement could begin."""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
tail = s[1005930:]

for i in range(0, 300, 50):
    print(i, repr(tail[i:i+50]))
