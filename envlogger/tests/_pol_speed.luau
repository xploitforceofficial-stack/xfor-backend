local Sandbox = require("../src/core/sandbox")
local Stdlib = require("../src/env/stdlib")
local fs = require("@lune/fs")
local process = require("@lune/process")
local source = fs.readFile(process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua")

local opts: any = { timeout = 120 }
if process.env.POLMODE == "raw" then opts = { timeout = 120, noInstrument = true } end
if process.env.POLMODE == "rawvm" then opts = { timeout = 120, noInstrument = true, noVmPatch = "true" } end

local t0 = os.clock()
local ok, res = pcall(function() return Sandbox.run(source, opts) end)
local dt = os.clock() - t0
print(string.format("mode=%s wall=%.1fs runOk=%s err=%s", tostring(process.env.POLMODE or "default"), dt, tostring(ok), ok and tostring(res.err) or tostring(res)))
if ok then
    print("outputs:", #(res.outputs or {}))
    local claims = 0
    for _, rec in ipairs(res.trace.records) do
        if rec.kind == "note" and tostring(rec.expression):find("budget", 1, true) then claims += 1 end
    end
    print("budget notes:", claims)
end
local log = Stdlib.envCallLog()
print("envcall header:", log:sub(1, 30))
print("string.sub calls:", tostring(Stdlib.__stats["string.sub"]), "bit32.band:", tostring(Stdlib.__stats["bit32.band"]))
