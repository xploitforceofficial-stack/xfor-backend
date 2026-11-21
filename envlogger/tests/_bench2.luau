local Sandbox = require("../src/core/sandbox")
local process = require("@lune/process")
local body = [[
local s = string.rep("abcdefghij", 200)
local acc = 0
for i = 1, 100000 do
    acc = acc + #string.sub(s, (i % 1900) + 1, (i % 1900) + 1)
    acc = acc + bit32.band(i, 1)
end
return acc
]]
for _, mode in ipairs({ "default", "raw" }) do
    local opts: any = { timeout = 120 }
    if mode == "raw" then opts.noInstrument = true end
    local t0 = os.clock()
    local ok, res = pcall(function() return Sandbox.run(body, opts) end)
    print(string.format("mode=%s wall=%.2fs ok=%s", mode, os.clock() - t0, tostring(ok)))
end

local concatBody = [[
local acc = ""
for i = 1, 20000 do acc = acc .. "x" end
return #acc
]]
local t1 = os.clock()
local ok2 = pcall(function() return Sandbox.run(concatBody, { timeout = 60 }) end)
print(string.format("concat-wall=%.2fs ok=%s", os.clock() - t1, tostring(ok2)))
