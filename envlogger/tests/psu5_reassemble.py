"""Assemble the REAL v5 code: the VM body lives INSIDE the long string and continues
after the close at 1005928. Build:

  for l,e in pairs({(function(e,...) <vmbody-from-string-tail> <post-close tail> end)(({<env>}),...)}) do return e end

vmbody starts at the last top-level statement boundary inside the string: find the
'for l,e in pairs' equivalent inside? Simpler: the in-string code from the first
'local function o(n,e,...)' (offset 1000532) — but earlier recon used that and got
a valid parse with the tail from the file end. Reuse that: body = s[1000524+8:] was
'local function o(n,e,...)...' through EOF. That INCLUDES the ']]' chars and tail.
So: body = s[1000532:] with the ']]' at 1005928-1005929 REMOVED (they're the string
close, not code). Everything else is real code.
"""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
body = s[1000532:1005928] + s[1005930:]
print('body len:', len(body))
print('body head:', repr(body[:60]))
print('body @ around close join:', repr(body[1005928-1000532-40:1005928-1000532+60]))

print('body end:', repr(body[-80:]))

out = 'for l,e in pairs({(function(e,...)' + body + '\nend)(({}),...)}) do return e end;'
open('Samples/PSU/v5/_v5cand2.lua', 'w', encoding='latin1').write(out)
print('wrote _v5cand2.lua len', len(out))
