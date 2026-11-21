local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")

local source = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_tmp_ms3.lua")
local ok, res = pcall(function()
    return Sandbox.run(source, { timeout = 45, noInstrument = true, noVmPatch = "true" })
end)
if not ok then
    print("RUN FAILED:", res)
    return
end
print("sandbox ok=", tostring(res.ok), "err=", tostring(res.err))
for _, rec in ipairs(res.trace.records) do
    if rec.kind == "note" and type(rec.expression) == "string"
        and (rec.expression:find("crash trace", 1, true) or rec.expression:find("locals", 1, true)) then
        print("NOTE-FULL:", rec.expression)
        print("----")
    end
end
