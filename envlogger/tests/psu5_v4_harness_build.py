"""Build complete v4 harness: v4 source head (through the LZW call) + dump of the decoded result.
This proves we can run v4's deserializer standalone; the same shape will be grafted for v5."""
v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()

st = v4.find('return(function(l,...)')
en = v4.find(',(#R-G);') + len(',(#R-G);')
head = v4[st:en]
print("v4 head len:", len(head))

harness = head + """
-- HARNESS: dump the decoded LZW result (local that received it)
-- The LZW IIFE result was just assigned. Find the assignment: it ended '),(#R-G);'
-- The statement was: local <name>=(function(...)...end)("PSU|..."),(#R-G);
-- So the decoded string is in the first local declared right before 'local function n('
DUMP_OK = true
"""
open('Samples/PSU/v5/_v4_harness.lua', 'w', encoding='utf-8').write(harness)
print("saved _v4_harness.lua")

i = en - len(',(#R-G);')
seg = v4[max(0, i - 300):i]
print("\n=== 300 before the call close:")
print(seg)
