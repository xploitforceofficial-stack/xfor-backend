local g = getgenv and getgenv() or _G
local n = 0
for k, v in pairs(g) do n = n + 1 end
print("genventries", n)
print("has select", type(select))
print("has string", type(string))
