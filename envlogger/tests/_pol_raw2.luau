local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local source = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua")
for _, mode in ipairs({ "default", "raw" }) do
    local opts: any = { timeout = 12 }
    if mode == "raw" then opts.noInstrument = true end
    local ok, res = pcall(function() return Sandbox.run(source, opts) end)
    print("== " .. mode .. " ok=" .. tostring(ok))
    for _, rec in ipairs(res.trace.records) do
        if rec.kind == "note" then
            local e = tostring(rec.expression)
            local fu = e:find("__FUHD", 1, true) ~= nil
            print(string.format("   note fuhd=%s %s", tostring(fu), e:sub(1, 110)))
        end
    end
end
