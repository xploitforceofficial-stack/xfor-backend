local Sandbox = require("../src/core/sandbox")
local src = [[
local function fromHex(hex)
	return string.gsub(hex, "..", function(byte) return string.char(tonumber(byte, 16)) end)
end
local function toHex(value)
	local hex = string.gsub(value, ".", function(byte) return string.format("%02x", string.byte(byte)) end)
	return hex
end
local nfc = utf8.nfcnormalize(fromHex("e1848fe185a9e186ade18492e185a2e186a9" .. "e18486e185a8e18481e185a2e186ba" .. "e18492e185a4e186b5"))
local nfd = utf8.nfdnormalize(fromHex("eabf94ebbdb0eb9ebaeb91b3ebb9a3eb9a89"))
print("nfc|", tostring(#nfc), tostring(toHex(nfc)))
print("nfd|", tostring(#nfd), tostring(toHex(nfd)))
local g = utf8.graphemes(utf8.char(128512, 128513))
print("graphemes ok|", tostring(g ~= nil))
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 60 })
if not ok then print("sandbox error:", res) return end
print("ok:", res.ok, "err:", res.err)
for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
