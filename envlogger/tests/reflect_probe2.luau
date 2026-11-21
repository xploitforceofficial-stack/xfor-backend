local roblox = require("@lune/roblox")
local db = roblox.getReflectionDatabase()

local names = {
	"getClasses", "getEnums", "getDataTypes", "getServices", "getCreatable",
	"getClass", "getEnum", "getDataType", "getAllClasses", "getAllEnums",
	"findClass", "findEnum", "classes", "enums", "dataTypes",
}
for _, n in ipairs(names) do
	local fn = (db :: any)[n]
	if fn ~= nil then
		local ok, res = pcall(fn, db)
		print(string.format("%-16s -> %s %s", n, tostring(ok),
			ok and (typeof(res) .. " len=" .. tostring(#(res :: any))) or tostring(res)))
	else
		print(string.format("%-16s -> absent", n))
	end
end

local ok2, cls = pcall(function()
	return (db :: any):getClasses()
end)
if ok2 and cls then
	print("classes count:", #cls)
	local first = cls[1]
	print("first keys:")
	if typeof(first) == "table" then
		for k, v in pairs(first) do
			print("   ", k, typeof(v), typeof(v) == "table" and #v or tostring(v))
		end
	end
	for _, c in ipairs(cls) do
		if c.Name == "Path2D" then
			print("Path2D:", "super=", tostring(c.Superclass), "tags=", tostring(c.Tags))
			for _, m in ipairs(c.Members or {}) do
				if m.MemberType == "Function" then
					print("   fn:", m.Name, m.Parameters and #m.Parameters or 0)
				end
			end
		end
	end
end
