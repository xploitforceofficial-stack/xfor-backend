local PropDefaults = require("../src/env/propdefaults")
print("classes:", PropDefaults.count())

local built = 0
PropDefaults.installResolver(function(constructor: string, args: { any }): any
	built += 1
	if constructor == "EnumItem" then
		return { fakeEnumItem = args[2] or args[1] }
	end
	return { fake = constructor }
end)

local materialized = PropDefaults.materialize()
print("materialized classes:", (function()
	local n = 0
	for _ in pairs(materialized) do n += 1 end
	return n
end)())
print("resolver calls:", built)

local hinge = materialized["HingeConstraint"]
if hinge then
	print("HingeConstraint.ActuatorType:", tostring(hinge.ActuatorType))
	print("HingeConstraint.Enabled:", tostring(hinge.Enabled))
else
	print("NO HingeConstraint entry!")
end

local bloom = materialized["BloomEffect"]
if bloom then
	print("BloomEffect.Intensity:", tostring(bloom.Intensity))
end
