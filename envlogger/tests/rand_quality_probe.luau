local Sandbox = require("../src/core/sandbox")

local src = [[
-- 1. precision: the old LCG made every value a multiple of 2^-31
local r = Random.new(177465824)
local coarse = 0
local sample = {}
for i = 1, 200 do
    local v = r:NextNumber()
    sample[#sample + 1] = v
    if math.abs(v * 2147483647 - math.floor(v * 2147483647 + 0.5)) < 1e-12 then
        coarse += 1
    end
end
print("coarse-31bit-multiples:", coarse, "of 200")
print("range ok:", sample[1] >= 0 and sample[1] < 1)

-- 2. two unseeded generators must not agree
local a = Random.new():NextNumber()
local b = Random.new():NextNumber()
print("unseeded distinct:", a ~= b)

-- 3. same seed must reproduce
local s1 = Random.new(12345):NextNumber()
local s2 = Random.new(12345):NextNumber()
print("same seed reproducible:", s1 == s2)

-- 4. clone stays in lockstep with its source
local src2 = Random.new(999)
local clone = src2:Clone()
print("clone lockstep:", clone:NextNumber() == src2:NextNumber())
print("clone lockstep2:", clone:NextNumber() == src2:NextNumber())

-- 5. distribution sanity over integers
local counts = { 0, 0, 0, 0, 0 }
local gen = Random.new(7)
for i = 1, 5000 do
    local v = gen:NextInteger(1, 5)
    counts[v] = counts[v] + 1
end
print("int buckets:", counts[1], counts[2], counts[3], counts[4], counts[5])

-- 6. argument validation
print("int no args:", pcall(function() return gen:NextInteger() end))
print("int float:", pcall(function() return gen:NextInteger(1.5, 3) end))
print("num 1 arg:", pcall(function() return gen:NextNumber(5) end))

-- 7. other members
print("unit vector length:", (gen:NextUnitVector().Magnitude - 1) < 1e-9)
local list = { 1, 2, 3, 4, 5, 6, 7, 8 }
gen:Shuffle(list)
print("shuffle keeps size:", #list == 8, "sorted:", table.concat(list, ","))
print("typeof:", typeof(gen), "tostring:", tostring(gen))
]]

local result = Sandbox.run(src, { timeout = 60, maxExplored = 0 })
print("ok:", result.ok, "err:", tostring(result.err):sub(1, 140))
for _, entry in ipairs(result.outputs or {}) do
	print("  " .. tostring(entry.text))
end
