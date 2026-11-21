local LuraphExtract = require("../src/core/luraph_extract")

local passed = 0
local failed = 0

local function check(name, got, expected)
    if got == expected then
        passed += 1
    else
        failed += 1
        print("FAIL: " .. name .. " got=" .. tostring(got) .. " expected=" .. tostring(expected))
    end
end

local luraphBody = "Ef=function(I,p,y,L,O,V,f,e) local v=true while v do if I<=100 then return end end end"
check("old luraph detected", LuraphExtract.isLuraphSource(string.rep("x", 600) .. luraphBody), true)
check("short text rejected", LuraphExtract.isLuraphSource("print('hi')"), false)

local newLuraph = "while H do if x<=3 then buffer.readu8(b, i) end end"
check("new luraph detected", LuraphExtract.isLuraphSource(string.rep("y", 600) .. newLuraph), true)
check("non-luraph rejected", LuraphExtract.isLuraphSource(string.rep("z", 600) .. "while true do local x = math.random() end"), false)

local ktable = LuraphExtract.extractKTable('K[0x41] = "hello" K[0x42] = "world"')
check("ktable hex 0x41", ktable["0x41"], "hello")
check("ktable hex 0x42", ktable["0x42"], "world")

local ktable2 = LuraphExtract.extractKTable('{ [1] = "first" [2] = "second" }')
check("ktable decimal 1", ktable2["[1]"], "first")
check("ktable decimal 2", ktable2["[2]"], "second")

local src = "while v do if I<=100 then return end end"
local patched = LuraphExtract.patchDispatcher(src)
check("dispatcher patched", patched:find("__LPH_REG_TRACE__") ~= nil, true)
check("dispatcher no-match", LuraphExtract.patchDispatcher("while true do x() end"):find("__LPH_REG_TRACE__") == nil, true)

local concatSrc = 'local s = t[a]..t[b]'
local concatPatched = LuraphExtract.patchByteConcat(concatSrc)
check("byte concat single-indexed", concatPatched:find("__LPH_STR_TRACE__") ~= nil, true)

local decoders = LuraphExtract.findDecodeFunctions(
    "local function D(s,k) return string.char(string.byte(s) bxor k) end"
)
check("decoder found", #decoders >= 1, true)
check("decoder name", decoders[1].name, "D")

local ltHex = LuraphExtract.patchDispatcher("while true do if a<0x10 then x() end end")
check("while-true lt hex patched", ltHex:find("__LPH_REG_TRACE__") ~= nil, true)

local ltDec = LuraphExtract.patchDispatcher("while true do if a<10 then x() end end")
check("while-true lt dec patched", ltDec:find("__LPH_REG_TRACE__") ~= nil, true)

local gtDec = LuraphExtract.patchDispatcher("while true do if a>10 then x() end end")
check("while-true gt dec patched", gtDec:find("__LPH_REG_TRACE__") ~= nil, true)

local repHex = LuraphExtract.patchDispatcher("repeat if a<0x20 then x() end until b")
check("repeat lt hex patched", repHex:find("__LPH_REG_TRACE__") ~= nil, true)

local repDec = LuraphExtract.patchDispatcher("repeat if a<=99 then x() end until b")
check("repeat le dec patched", repDec:find("__LPH_REG_TRACE__") ~= nil, true)

local bracketSrc = 'local s = [[while H do if x<=3 then buffer.readu8(b, i) end end]] return s'
local chunks = LuraphExtract.extractEmbeddedChunks(bracketSrc, 10)
local foundBracket = false
for _, c in ipairs(chunks) do
    if c:find("buffer.readu8", 1, true) then
        foundBracket = true
        check("bracket payload is exact", c, "while H do if x<=3 then buffer.readu8(b, i) end end")
    end
end
check("level-0 long bracket extracted", foundBracket, true)

local eqSrc = 'local s = [=[while H do if y>5 then return end end]=] return s'
local eqChunks = LuraphExtract.extractEmbeddedChunks(eqSrc, 10)
local foundEq = false
for _, c in ipairs(eqChunks) do
    if c:find("return end", 1, true) then
        foundEq = true
    end
end
check("level-1 long bracket extracted", foundEq, true)

local good = "local x = 1 return x"
check("salvage loadable raw", LuraphExtract.salvageLoadable(good), good)

local bannerGood = "-- banner junk here\nreturn(function(...) return ... end)"
local salv = LuraphExtract.salvageLoadable(bannerGood)
check("salvage skips banner", salv ~= nil, true)
if salv then
    check("salvage payload kept", salv:find("return(function", 1, true) ~= nil, true)
end

check("salvage rejects binary", LuraphExtract.salvageLoadable(string.rep("\0", 500)), nil)
check("salvage rejects empty", LuraphExtract.salvageLoadable(""), nil)

check("short chunks skipped", #LuraphExtract.extractEmbeddedChunks("local s = [[tiny]]", 100), 0)
check("binary skipped", #LuraphExtract.extractEmbeddedChunks('x = "' .. string.rep("\1\2\3\4", 200) .. '"', 100), 0)

check("banner detected", LuraphExtract.isLuraphSource("Luraph Obfuscator" .. string.rep("z", 600)), true)
check("LPH@ loadstring detected", LuraphExtract.isLuraphSource("LPH@" .. string.rep("q", 500) .. " loadstring"), true)

print(string.format("luraph_extract: %d passed, %d failed", passed, failed))
