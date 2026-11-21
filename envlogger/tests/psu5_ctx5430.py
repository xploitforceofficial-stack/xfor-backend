"""Show context at parse error position 5430 in v2 (raw join) candidate.
Position in the candidate = 5430; wrapper prefix is 34 chars, so body offset = 5396.
body starts at file offset 1000532, so file offset = 1005928. The join! But v2 is raw join.
Wait — error at 5430 in candidate: check both v1 and v2 contexts."""
for name in ['_v5cand_v1.lua', '_v5cand_v2.lua']:
    s = open('Samples/PSU/v5/' + name, encoding='latin1').read()
    print(name)
    print(repr(s[5380:5470]))
    print()
