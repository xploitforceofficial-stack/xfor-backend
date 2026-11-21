local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Zstd = require("../src/env/zstd")

local report = fs.readFile([[C:\Users\Sandr\AppData\Local\Temp\opencode\p_s2.out.lua]])
local marker = "DecompressBuffer(buffer.fromstring("
local at = report:find(marker, 1, true)
if not at then
	print("marker not found in report")
	return
end
local rest = report:sub(at + #marker)
local out = {}
local i = 2
while i <= #rest do
	local c = rest:sub(i, i)
	if c == '"' then
		break
	elseif c == "\\" then
		local nxt = rest:sub(i + 1, i + 1)
		if nxt:match("%d") then
			local j = i + 1
			local digits = ""
			while j <= #rest and #digits < 3 and rest:sub(j, j):match("%d") do
				digits = digits .. rest:sub(j, j)
				j = j + 1
			end
			out[#out + 1] = string.char(tonumber(digits))
			i = j
		else
			local map = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ['"'] = '"' }
			out[#out + 1] = map[nxt] or nxt
			i = i + 2
		end
	else
		out[#out + 1] = c
		i = i + 1
	end
end
local blob = table.concat(out)
print(string.format("blob len=%d first4=%02X %02X %02X %02X", #blob, blob:byte(1), blob:byte(2), blob:byte(3), blob:byte(4)))
print("readLE=" .. string.format("%X", Zstd._debug.readLE(blob, 1, 4)) .. " MAGIC=" .. string.format("%X", Zstd._debug.ZSTD_MAGIC))
print("isFrame=" .. tostring(Zstd.isFrame(blob)))
if not Zstd.isFrame(blob) then
	return
end

local t0 = os.clock()
local res, err = Zstd.decompress(blob)
local dt = os.clock() - t0
if not res then
	print("FAIL: " .. tostring(err))
	return
end
print(string.format("decompressed %d bytes in %.1fs", #res, dt))
print("--- first 300 chars ---")
print(res:sub(1, 300))
local ok, e = pcall(luau.load, res, "@stage")
print("compiles as luau: " .. tostring(ok) .. " " .. tostring(not ok and e or ""))
