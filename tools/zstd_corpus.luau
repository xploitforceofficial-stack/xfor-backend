local fs = require("@lune/fs")

local Zstd = require("../envlogger/src/env/zstd")

local dir = "tools/zstd-corpus/gen"
if not fs.isDir(dir) then
    print("no corpus; run python tools/zstd_gen.py first")
    return
end

local names = {}
for _, f in fs.readDir(dir) do
    if f:sub(-4) == ".zst" then
        table.insert(names, f:sub(1, -5))
    end
end
table.sort(names)

local pass, fail = 0, 0
for _, name in ipairs(names) do
    local frame = fs.readFile(dir .. "/" .. name .. ".zst")
    local want = fs.readFile(dir .. "/" .. name .. ".raw")
    local ok, out, err = pcall(Zstd.decompress, frame)
    if not ok then
        print(string.format("FAIL %-14s raised: %s", name, tostring(out)))
        fail += 1
    elseif type(out) ~= "string" then
        print(string.format("FAIL %-14s nil: %s", name, tostring(err)))
        fail += 1
    elseif out == want then
        print(string.format("ok   %-14s %d bytes", name, #out))
        pass += 1
    else
        local firstDiff = 0
        local n = math.min(#out, #want)
        for i = 1, n do
            if out:byte(i) ~= want:byte(i) then
                firstDiff = i
                break
            end
        end
        if firstDiff == 0 then firstDiff = n + 1 end
        local ctx = ""
        if firstDiff >= 1 and firstDiff <= n then
            ctx = string.format(" at %d: got %s want %s", firstDiff,
                out:sub(firstDiff, firstDiff + 7):gsub("%c", "."),
                want:sub(firstDiff, firstDiff + 7):gsub("%c", "."))
        end
        print(string.format("FAIL %-14s got %d want %d%s", name, #out, #want, ctx))
        fail += 1
    end
end
print(string.format("\n%d passed, %d failed", pass, fail))
