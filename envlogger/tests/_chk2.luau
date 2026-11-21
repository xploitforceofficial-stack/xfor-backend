local fs = require("@lune/fs")
local luau = require("@lune/luau")
local files = {
	"src/core/sandbox.luau",
	"src/env/roblox.luau",
	"src/env/services.luau",
	"src/main.luau",
	"src/core/srcedit.luau",
}
for _, p in ipairs(files) do
	local okRead, src = pcall(fs.readFile, p)
	if not okRead then
		print(p .. ": READ FAIL " .. tostring(src))
		continue
	end
	local ok, err = pcall(luau.load, src, "@" .. p)
	print(string.format("%-28s compile=%s %s", p, tostring(ok), tostring(not ok and err or "")))
end
