local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("../Samples/Moonveli/v2.0.23/1.lua")

local ok, res = pcall(Sandbox.run, source, { timeout = 60, maxNest = 1 })
if not ok then
	print("sandbox failed:", res)
	return
end

print("ok:", res.ok, "err:", res.err)
print("decrypted:", res.decryptedStringCount)
print("stages:", res.stages and #res.stages or 0)
print("unrolled:", res.unrolledSource and #res.unrolledSource or 0)

local strs = res.decryptedStrings or {}
local head, tail = {}, {}
for i = 1, math.min(#strs, 200) do
	head[i] = strs[i]
end
for i = math.max(1, #strs - 40), #strs do
	tail[#tail + 1] = strs[i]
end
print("tail 40 chunks (in order):")
local buf = {}
for _, s in ipairs(tail) do
	buf[#buf + 1] = s:gsub("%c", " ")
end
print(table.concat(buf, " | "))

fs.writeFile("C:/Users/Sandr/AppData/Local/Temp/mv_dump2.json", serde.encode("json", {
	strs = strs,
	stages = res.stages,
}, true))
print("wrote mv_dump2.json")
