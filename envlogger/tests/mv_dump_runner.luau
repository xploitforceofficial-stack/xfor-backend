local fs = require("@lune/fs")
local serde = require("@lune/serde")

local inputPath = arg and arg[1] or "../Samples/Moonveli/v2.0.23/1.lua"
local outPath = arg and arg[2] or "C:/Users/Sandr/AppData/Local/Temp/mv_dump.json"
local budget = tonumber(arg and arg[3] or nil) or 45

local source = fs.readFile(inputPath)

local Sandbox = require("../src/core/sandbox")

local ok, res = pcall(Sandbox.run, source, {
	timeout = budget,
	maxNest = 1,
	noInstrument = true,
	maxExplored = 0,
	traceLimit = 0,
})

if not ok then
	print("sandbox failed:", res)
	return
end

local payload = {
	ok = res.ok,
	err = res.err,
	exhausted = res.exhausted,
	exhaustedReason = res.exhaustedReason,
	decryptedCount = res.decryptedStringCount,
	decrypted = res.decryptedStrings,
	outputs = res.outputs,
	stages = res.stages,
	vmTraceCount = res.vmTrace and #res.vmTrace or 0,
	vmTraceCapped = res.vmTraceCapped,
	vmTraceTail = nil,
	undefinedGlobals = res.undefinedGlobals,
}
if res.vmTrace and #res.vmTrace > 0 then
	local tail = {}
	local start = math.max(1, #res.vmTrace - 40)
	for i = start, #res.vmTrace do
		local rec = res.vmTrace[i]
		if type(rec) == "table" then
			local flat = {}
			for k, v in pairs(rec) do
				flat[k] = tostring(v)
			end
			tail[#tail + 1] = flat
		else
			tail[#tail + 1] = tostring(rec)
		end
	end
	payload.vmTraceTail = tail
end

local encoded = serde.encode("json", payload, true)
fs.writeFile(outPath, encoded)
print("wrote", outPath, "count:", res.decryptedStringCount, "ok:", res.ok, "err:", res.err)
