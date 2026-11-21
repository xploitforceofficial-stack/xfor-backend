local fs = require("@lune/fs")
local dir = "tools/work_s2/opcodes"
local bad, n = {}, 0
for _, f in fs.readDir(dir) do
    if f:sub(-4) == ".lua" then
        n += 1
        local src = fs.readFile(dir .. "/" .. f)
        local chunk, err = loadstring(src, "@" .. f)
        if not chunk then
            table.insert(bad, f .. ": " .. tostring(err))
        end
    end
end
print("checked", n, "bad", #bad)
for i = 1, math.min(#bad, 10) do
    print(" ", bad[i])
end
