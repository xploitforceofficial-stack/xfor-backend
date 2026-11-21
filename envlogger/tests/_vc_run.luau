local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local source = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_valuecheck.lua")
local ok, res = pcall(function() return Sandbox.run(source, { timeout = 60 }) end)
print("ok=", tostring(ok), "err=", ok and tostring(res.err) or tostring(res))
print("outputs:", #(res.outputs or {}))
for _, rec in ipairs(res.trace.records) do
    print(rec.kind, tostring(rec.expression):sub(1, 160))
end
