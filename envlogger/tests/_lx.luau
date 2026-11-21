local fs = require("@lune/fs")
local LuraphExtract = require("../src/core/luraph_extract")

local function probe(path: string)
	local ok, src = pcall(fs.readFile, path)
	if not ok then
		print("READFAIL " .. path)
		return
	end
	print("== " .. path .. " len=" .. #src)
	print("isLuraph=" .. tostring(LuraphExtract.isLuraphSource(src)))
	local ok1, chunks = pcall(function()
		return LuraphExtract.extractEmbeddedChunks(src, 400)
	end)
	if ok1 then
		print("chunks n=" .. tostring(#chunks))
		for i = 1, math.min(#chunks, 8) do
			print("  chunk" .. i .. " len=" .. #chunks[i])
		end
	else
		print("chunks ERR " .. tostring(chunks))
	end
	local ok2, kt = pcall(function()
		return LuraphExtract.extractKTable(src)
	end)
	if ok2 then
		local n = 0
		local sample = ""
		for k, v in pairs(kt) do
			n = n + 1
			if n <= 6 then
				sample = sample .. " [" .. tostring(k) .. "]=" .. tostring(v):sub(1, 24)
			end
		end
		print("ktable n=" .. n .. sample)
	else
		print("ktable ERR " .. tostring(kt))
	end
	local ok3, dec = pcall(function()
		return LuraphExtract.findDecodeFunctions(src)
	end)
	if ok3 then
		print("decoders n=" .. tostring(#dec))
		for i = 1, math.min(#dec, 8) do
			print("  d" .. i .. " name=" .. tostring(dec[i].name) .. " line=" .. tostring(dec[i].line))
		end
	else
		print("decoders ERR " .. tostring(dec))
	end
end

probe("../Samples/Luraph/luraph-v14.6.lua")
probe("../Samples/Luraph/luraph-v14.7.lua")
probe("../Samples/Luraph/luraph-v14.8.lua")
print("DONE")
