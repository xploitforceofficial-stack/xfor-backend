local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")

local configs = {
	{ name = "default", opts = {} },
	{ name = "novmpatch", opts = { noVmPatch = true } },
	{ name = "noinstrument", opts = { noInstrument = true } },
	{ name = "both", opts = { noInstrument = true, noVmPatch = true } },
}
for _, c in ipairs(configs) do
	local opts = { timeout = 90, maxExplored = 0 }
	for k, v in pairs(c.opts) do opts[k] = v end
	local ok, res = pcall(Sandbox.run, src, opts)
	if not ok then
		print(c.name, "RUN-ERROR:", tostring(res):sub(1, 100))
	else
		local out = {}
		for _, e in ipairs(res.outputs or {}) do out[#out+1] = e.text end
		print(c.name, "ok=" .. tostring(res.ok), "err=" .. tostring(res.err):sub(1, 70), "out=" .. table.concat(out, "|"):sub(1, 90), "dec=" .. tostring(res.decryptedStringCount))
	end
end
