local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local source = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua")
local ok, res = pcall(function() return Sandbox.run(source, { timeout = 25 }) end)
print("ok=", tostring(ok))
if ok then
    for k, v in pairs(res) do
        local tv = type(v)
        if tv ~= "table" then print("  res." .. k, "=", tostring(v)) end
    end
    print("notes:")
    for _, rec in ipairs(res.trace.records) do
        print("   ", rec.kind, tostring(rec.expression):sub(1, 180))
    end
end
