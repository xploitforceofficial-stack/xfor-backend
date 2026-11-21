local fs = require("@lune/fs")

local tbl = fs.readFile("../Samples/PSU/v5/_envtable.luau.txt")
local chunk = tbl

local fn, err = loadstring(chunk)
if not fn then
	print("load failed:", tostring(err):sub(1, 200))
	return
end

local ok, result = pcall(fn)
if not ok then
	print("exec failed:", tostring(result):sub(1, 200))
	return
end

print("env table loaded, entries:", 0)
local n = 0
for _ in pairs(result) do n += 1 end
print("env table entries:", n)

local shown = 0
for k, v in pairs(result) do
	shown += 1
	if shown <= 40 then
		print(k, "=", v)
	end
end

local serde = require("@lune/serde")
fs.writeFile("../Samples/PSU/v5/_envtable.json", serde.encode("json", result, true))
print("saved json")
