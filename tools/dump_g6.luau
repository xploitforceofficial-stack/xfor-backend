local fs = require("@lune/fs")

local stageSrc = fs.readFile("tools/work/stage147_inst.lua")
local prog = fs.readFile("tools/work/prog_1.bin")

local doLoad = loadstring or load
local chunk = assert(doLoad(stageSrc, "=stage"))
local ok, res, g6, gy, og, ov, a49, arr, ent, upl, jl = pcall(function()
    return chunk(buffer.fromstring(prog))
end)
if not ok then
    error("stage failed: " .. tostring(res))
end
print("[run] stage ok g6=" .. #g6 .. " gy=" .. #gy)
print("[run] returned type=" .. type(res))
print("[run] load-phase chains=" .. #arr .. " entries=" .. (ent and #ent or 0))

if type(res) == "function" then
    local r1, err1 = pcall(res)
    print("[run] program ok=" .. tostring(r1) .. " err=" .. tostring(err1))
end
print("[run] dispatches=" .. #og .. " a49=" .. #a49)

local out = {}
for i = 1, #g6 do
    local e = g6[i]
    out[i] = string.format("%d\t%d\t%d\t%d\t%d\t%d", e.n, e.l3, e.H, e.A, e.Y, e.c)
end
fs.writeFile("tools/work/g6.tsv", table.concat(out, "\n") .. "\n")

local out2 = {}
for i = 1, #gy do
    local e = gy[i]
    out2[i] = string.format(
        "%d\tK=%d\top=%d\tZ=%d\tT=%d\tJ=%d\tG=%d\tH=%d",
        e.w, e.K, e.op, e.Z, e.T, e.J, e.G, e.H)
end
fs.writeFile("tools/work/gy.tsv", table.concat(out2, "\n") .. "\n")

local out3 = {}
for i = 1, #og do
    out3[i] = string.format("%s\t%s", tostring(og[i]), tostring(ov[i]))
end
fs.writeFile("tools/work/op.tsv", table.concat(out3, "\n") .. "\n")

local out4 = {}
for i = 1, #a49 do
    local e = a49[i]
    out4[i] = string.format("%d\t%s\t%s\t%s", e[1], tostring(e[2]), tostring(e[3]), tostring(e[4]))
end
fs.writeFile("tools/work/a49.tsv", table.concat(out4, "\n") .. "\n")

local out4b = {}
for c = 1, #arr do
    local e = arr[c]
    out4b[c] = string.format("%d\t%s\t%d", c, tostring(e.h), e.n)
end
fs.writeFile("tools/work/a49arr.tsv", table.concat(out4b, "\n") .. "\n")

local function cell(a, g)

    local ok, v = pcall(function()
        return a and a[g]
    end)
    if not ok or v == nil then
        return "-"
    end
    local ok2, s = pcall(tostring, v)
    if not ok2 then
        return "?"
    end

    return (s:gsub("[\t\r\n]", function(ch)
        if ch == "\t" then
            return "\\t"
        elseif ch == "\n" then
            return "\\n"
        end
        return "\\r"
    end))
end

local out5 = {}
local n = 0
for c = 1, #arr do
    local e = arr[c]
    for g = 1, e.n do
        n += 1
        out5[n] = string.format(
            "%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s",
            c, g,
            cell(e.t, g), cell(e.i, g), cell(e.w, g), cell(e.D, g),
            cell(e.f, g), cell(e.O, g), cell(e.z, g))
    end
end
fs.writeFile("tools/work/chains.tsv", table.concat(out5, "\n") .. "\n")
print("[run] chain slots=" .. n .. " chains=" .. #arr)

local out6 = {}
if ent ~= nil then
    local m = 0
    for k = 1, #ent do
        local e = ent[k]
        for g = 1, e.n do
            m += 1
            out6[m] = string.format(
                "%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s",
                tostring(e.h), g,
                cell(e.t, g), cell(e.i, g), cell(e.w, g), cell(e.D, g),
                cell(e.f, g), cell(e.O, g), cell(e.z, g))
        end
    end
end
if #out6 > 0 then
    fs.writeFile("tools/work/a49entry.tsv", table.concat(out6, "\n") .. "\n")
end
print("[run] entry chains=" .. (ent and #ent or 0))

local out7 = {}
if upl ~= nil then
    for k = 1, #upl do
        local e = upl[k]
        local path = tostring(e.path):gsub("[\t\r\n]", "?")
        out7[k] = string.format("%s\t%s\t%s\t%s", tostring(e.h), path, tostring(e.tp), tostring(e.v))
    end
end
if #out7 > 0 then
    fs.writeFile("tools/work/upvals.tsv", table.concat(out7, "\n") .. "\n")
end

local out8 = {}
if jl ~= nil then
    for k = 1, #jl do
        local e = jl[k]
        out8[k] = string.format("%s\t%s", tostring(e.f), tostring(e.b))
    end
end
if #out8 > 0 then
    fs.writeFile("tools/work/jlink.tsv", table.concat(out8, "\n") .. "\n")
end
print("[run] upvals=" .. #out7 .. " jlinks=" .. #out8)

print("[run] wrote g6.tsv, gy.tsv, op.tsv, a49.tsv, chains.tsv")
