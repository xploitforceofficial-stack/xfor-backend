local Spy = require("../src/core/spy")

local spyVal = Spy.new("workspace", {}, nil, false, 0)
local t2 = { x = spyVal }
local copy = Spy.unwrap(t2)
print("copy type:", type(copy))
local n = 0
for k, v in pairs(copy) do
	n += 1
	print("copy entry:", k, v, type(v))
end
print("entries:", n)
