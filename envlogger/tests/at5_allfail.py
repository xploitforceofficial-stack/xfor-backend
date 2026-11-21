"""Build at5_fixture_all.lua: same anti-tamper battery, but `check` records every
failure and keeps going, so one sandbox run lists ALL failing check ids."""
import hashlib
import re

SRC = "tests/at5_fixture.lua"
OUT = "tests/at5_fixture_all.lua"

text = open(SRC, encoding="utf-8", errors="replace").read()

m = re.search(r"local guardedSource = \[==\[\n(.*?)\n\]==\]", text, re.S)
assert m, "guarded source not found"
body = m.group(1)

old_detected = """    local function detected(reason)
        print("GET TF OUT BITCH SKID", reason)
        error("GET TF OUT BITCH SKID", 0)
    end"""
new_detected = """    local allFails = {}
    local function detected(reason)
        allFails[#allFails + 1] = tostring(reason)
        print("FAIL", tostring(reason))
    end"""
assert old_detected in body, "detected() body mismatch"
body = body.replace(old_detected, new_detected, 1)

body = re.sub(r'check\(\s*string\.find\(', 'checkFind(', body)
body = re.sub(r'checkFind\((.+?),\s*1,\s*true\)\s*~=\s*nil,',
              r'checkFind(\1,', body, flags=re.S)
helper = ('    local function checkFind(text, needle, reason)\n'
          '        if type(text) ~= "string" or\n'
          '            string.find(text, needle, 1, true) == nil then\n'
          '            detected(reason)\n'
          '        end\n'
          '    end\n')
body = body.replace('    local function check(value, reason)',
                    helper + '    local function check(value, reason)', 1)

start = body.find('    local screenGui = Instance.new("ScreenGui")')
end = body.find('    screenGui:Destroy()')
if start != -1 and end != -1:
    body = body[:start] + '    --[[ Path2D section skipped: class not implemented ]]\n' + body[end + len('    screenGui:Destroy()\n'):]

old_tail = '    runChecks()\n    print("Be A Good Boy And Dont Skid")'
new_tail = ('    runChecks()\n'
            '    print("FAILCOUNT", #allFails)\n'
            '    for _, reason in ipairs(allFails) do\n'
            '        print("FAIL", reason)\n'
            '    end\n'
            '    print("Be A Good Boy And Dont Skid")')
assert old_tail in body, "tail mismatch"
body = body.replace(old_tail, new_tail, 1)

guarded = body + "\n"
h = 5381
for ch in guarded.encode("utf-8"):
    h = (h * 33 + ch) % 4294967296

out = text[:m.start(1)] + body + text[m.end(1):]
out = re.sub(r"if checksum\(guardedSource\) ~= \d+ then", f"if checksum(guardedSource) ~= {h} then", out)
open(OUT, "w", encoding="utf-8", newline="\n").write(out)
print("wrote", OUT, "checksum", h, "len", len(guarded))
