local Deobfuscation = require("../src/core/deobfuscation")

local passed = 0
local failed = 0

local function check(name: string, condition: boolean, detail: string?)
    if condition then
        passed += 1
    else
        failed += 1
        print("[FAIL] " .. name .. (detail and (": " .. detail) or ""))
    end
end

do
    local source = 'local t = { [0xb283] = "LocalPlayer", [0xc25b] = "Name" }'
    local tbl = Deobfuscation.extractStringTableFromSource(source)
    check("extractStringTableFromSource finds hex keys", tbl["0xb283"] == "LocalPlayer")
    check("extractStringTableFromSource finds second key", tbl["0xc25b"] == "Name")
end

do
    local trace = { records = {
        { kind = "note", expression = 'k[0x1234] = "hello"' },
        { kind = "note", expression = 'd[0xabcd] = "world"' },
        { kind = "call", expression = "print(x)" },
    }}
    local tbl = Deobfuscation.extractStringTable(trace)
    check("extractStringTable from trace", tbl["k[0x1234]"] == "hello")
end

do
    local source = [[if j<=0x31 then --didn't ran
    print("dead")
elseif j<=0xba then --did ran
    print("live")
end]]
    local result = Deobfuscation.eliminateDeadCode(source)
    check("eliminateDeadCode removes dead", not result:find("dead code"))
    check("eliminateDeadCode keeps live", result:find("live") ~= nil)
end

do
    local source = "local info = debug.getinfo(print)\nlocal env = getfenv(0)\nlocal mt = getmetatable(game)"
    local results = Deobfuscation.detectAntiTamper(source)
    local found = {}
    for _, r in ipairs(results) do
        if r.detected then found[r.name] = true end
    end
    check("detect debug.getinfo", found["debug.getinfo native check"])
    check("detect getfenv(0)", found["getfenv(0) check"])
    check("detect metatable", found["metatable check"])
end

do
    local stages = {
        { source = "print('stage 1')", origin = "loadstring" },
        { source = "print('stage 2')", origin = "loadstring" },
        { source = "print('stage 3')", origin = "loadstring" },
    }
    check("shouldUnroll true", Deobfuscation.shouldUnroll(stages) == true)
    local unrolled = Deobfuscation.unrollStages(stages)
    check("unrollStages includes stages",
        unrolled:find("stage 1") and unrolled:find("stage 2") and unrolled:find("stage 3"))
    check("unrollStages has header",
        unrolled:find("Unrolled multi-stage loader", 1, true))
end

do
    local stages = { { source = "print('x')", origin = "loadstring" } }
    check("shouldUnroll false single", Deobfuscation.shouldUnroll(stages) == false)
end

do
    local stages = {}
    check("shouldUnroll false empty", Deobfuscation.shouldUnroll(stages) == false)
    check("unrollStages empty", Deobfuscation.unrollStages(stages):find("0 stages"))
end

print(string.format("\n%d passed, %d failed", passed, failed))
