local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("../Samples/Moonveli/v2.0.23/1.lua")

local ok, res = pcall(Sandbox.run, source, { timeout = 45, maxNest = 1 })

if not ok then
	print("sandbox failed:", res)
	return
end

print("ok:", res.ok, "err:", res.err, "decrypted:", res.decryptedStringCount)
print("bxor log entries:", res.bxorLog and #res.bxorLog or 0)

local payload = {
	bxor = res.bxorLog,
	strs = {},
}
if res.decryptedStrings then
	for i = 1, math.min(#res.decryptedStrings, 400) do
		payload.strs[i] = res.decryptedStrings[i]
	end
end

fs.writeFile("C:/Users/Sandr/AppData/Local/Temp/mv_bxor.json", serde.encode("json", payload, true))
print("wrote mv_bxor.json")
