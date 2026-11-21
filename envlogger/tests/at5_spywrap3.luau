local Spy = require("../src/core/spy")

local spyVal = Spy.new("workspace", {}, nil, false, 0)
local t2 = { x = spyVal }

local copy = {}
for key, item in pairs(t2) do
	local u = Spy.unwrap(item)
	print("unwrapping", key, ":", type(u), u)
	copy[key] = u
end
print("copy.x:", copy.x)
