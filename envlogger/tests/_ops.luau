local results = {}
local function t(name, fn)
	local ok, err = pcall(fn)
	table.insert(results, string.format("%-22s %s", name, tostring(ok)))
end

t("1 << 2", function() return 1 << 2 end)
t("8 >> 2", function() return 8 >> 2 end)
t("1 & 3", function() return 1 & 3 end)
t("1 | 2", function() return 1 | 2 end)
t("1 ~ 2", function() return 1 ~ 2 end)
t("bit32.lshift", function() return bit32.lshift(1, 2) end)
t("bit32.band", function() return bit32.band(7, 3) end)
t("bit32.rshift", function() return bit32.rshift(8, 2) end)
t("bit32.clz", function() return bit32.clz(1) end)
t("bit32.bor", function() return bit32.bor(1, 2) end)
t("bit32.bxor", function() return bit32.bxor(5, 3) end)
t("2^10 pow", function() return 2 ^ 10 end)
t("// floor div", function() return 7 // 2 end)
t("+= compound", function() local x = 1 x += 1 return x end)
t("& mask expr", function() local a, b = 5, 3 return a & b end)

print(table.concat(results, "\n"))
