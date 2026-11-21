math.randomseed(177465824)

local seq = {}
for i = 1, 10 do
	seq[i] = math.random()
end

print("first 6 math.random() after randomseed(177465824):")
for i = 1, 6 do
	print(string.format("  %d: %.17g", i, seq[i]))
end

print("targets:")
print("  v1 0.9598971928030796")
print("  v3 0.027539190730015265")
print("  v4 0.3377740061710911")

math.randomseed(177465824)
local a = math.random()
local i2 = math.random(189, 1164)
local b = math.random()
local c = math.random()
print(string.format("interleaved: a=%.17g int=%d b=%.17g c=%.17g", a, i2, b, c))
print("want:        a=0.9598971928030796 int=889 b=0.027539190730015265 c=0.3377740061710911")

local function ulps(v)
	return (v * 2 ^ 53) % 1, (v * 2 ^ 64) % 1
end
print("v1 frac*2^53:", (select(1, ulps(0.9598971928030796))), " frac*2^64:", (select(2, ulps(0.9598971928030796))))
print("v3 frac*2^53:", (select(1, ulps(0.027539190730015265))), " frac*2^64:", (select(2, ulps(0.027539190730015265))))
