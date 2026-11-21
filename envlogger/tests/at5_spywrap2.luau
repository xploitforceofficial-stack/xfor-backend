local Spy = require("../src/core/spy")

local spyVal = Spy.new("workspace", {}, nil, false, 0)
print("Spy.is(spyVal):", Spy.is(spyVal))
local t2 = { x = spyVal }
print("rawget x exists:", t2.x ~= nil)
local n = 0
for k, v in pairs(t2) do
	n += 1
	print("iter:", k, type(v))
end
print("orig entries:", n)
local copy = Spy.unwrap(t2)
print("copy == t2:", copy == t2)
