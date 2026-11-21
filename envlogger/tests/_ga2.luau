local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Instrument = require("../src/core/instrument")

local src = fs.readFile("../Samples/Luraph/luraph-v14.7.lua")
print("src len=" .. #src)

local t0 = os.clock()
local out, err, n = Instrument.guardArith(src)
print(string.format("guardArith t=%.1f n=%s err=%s outLen=%s", os.clock() - t0, tostring(n), tostring(err), tostring(out and #out)))

if out then
	local ok, e = pcall(luau.load, out, "@guarded")
	print("compiles=" .. tostring(ok) .. "  " .. tostring(not ok and e or ""))
	if not ok then

		local msg = tostring(e)
		local ln = msg:match(":(%d+):")
		if ln then
			local lineNo = tonumber(ln)
			local sofar, pos = 0, 1
			for _ = 1, lineNo do
				local nl = out:find("\n", pos, true)
				if not nl then break end
				sofar = nl
				pos = nl + 1
			end
			local seg = out:sub(sofar + 1, sofar + 400)
			print("around line " .. lineNo .. ": " .. seg)
		end
	end
end
