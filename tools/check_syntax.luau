local fs = require("@lune/fs")

local args = require("@lune/process").args
if #args < 1 then
    print("usage: lune run tools/check_syntax <workdir> [...]")
    return
end
local names = { "simple.lua", "lifted.lua" }
local bad = 0
for _, dir in ipairs(args) do
    for _, name in ipairs(names) do
        local path = dir .. "/" .. name
        local okSrc, src = pcall(fs.readFile, path)
        if okSrc then
            local chunk, err = loadstring(src, "@" .. path)
            if chunk then
                print(string.format("OK   %s (%d bytes)", path, #src))
            else
                bad += 1
                print(string.format("FAIL %s: %s", path, tostring(err)))
            end
        else
            print(string.format("skip %s (missing)", path))
        end
    end
end
print(bad == 0 and "all artifacts parse" or (bad .. " artifact(s) failed"))
