local s = string.rep("abcdefghij", 200)
local t0 = os.clock()
local acc = 0
for i = 1, 100000 do
    acc = acc + #string.sub(s, (i % 1900) + 1, (i % 1900) + 1)
    acc = acc + bit32.band(i, 1)
end
print("BENCH_ELAPSED", string.format("%.3f", os.clock() - t0), acc)
