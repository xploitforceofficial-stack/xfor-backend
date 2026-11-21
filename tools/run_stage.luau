local fs = require("@lune/fs")

local STAGE = "tools/work/stage147.lua"
local PROG = "tools/work/prog_1.bin"

local stageSrc = fs.readFile(STAGE)
local prog = fs.readFile(PROG)

local doLoad = loadstring or load
if doLoad == nil then
    error("no load/loadstring in this Lune")
end
local chunk, err = doLoad(stageSrc, "=stage")
if not chunk then
    error("stage load failed: " .. tostring(err))
end

local ok, res = pcall(function()
    return chunk(buffer.fromstring(prog))
end)
print("[run_stage] ok=" .. tostring(ok) .. " err=" .. tostring(res) .. " type=" .. type(res))
if ok and type(res) == "table" then
    local n = 0
    for _ in pairs(res) do
        n += 1
    end
    print("[run_stage] result table keys=" .. tostring(n))
end
