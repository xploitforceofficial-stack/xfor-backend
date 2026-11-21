local roblox = require("@lune/roblox")
local db = roblox.getReflectionDatabase()

for _, key in ipairs({
	"Classes", "Enums", "DataTypes", "Services", "Version",
	"Creatable", "AllClasses", "allClasses", "classes",
}) do
	local ok, v = pcall(function()
		return (db :: any)[key]
	end)
	if ok then
		local shape = typeof(v)
		local len = ""
		if shape == "table" then
			local n = 0
			for _ in pairs(v) do
				n += 1
			end
			len = " entries=" .. n
		end
		print(string.format("%-12s -> %s%s %s", key, shape, len, shape ~= "table" and tostring(v) or ""))
	else
		print(string.format("%-12s -> error %s", key, tostring(v)))
	end
end
