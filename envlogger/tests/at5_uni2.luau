local Sandbox = require("../src/core/sandbox")
local function run(label, body)
	local ok, res = pcall(Sandbox.run, body, { timeout = 30 })
	if not ok then print(label .. "| sandbox error: " .. tostring(res)) return end
	print(label .. "| ok=" .. tostring(res.ok) .. " err=" .. tostring(res.err))
	for _, e in ipairs(res.outputs or {}) do print("   OUT|" .. tostring(e.text)) end
end
run("graphemes", [[
local g = utf8.graphemes("abc")
local n = 0
for _ in g do n = n + 1 end
print("count", n)
]])
run("nfcnorm-ascii", [[ print(utf8.nfcnormalize("abc")) ]])
run("nfdnorm-ascii", [[ print(utf8.nfdnormalize("abc")) ]])
run("nfcnorm-utf8", [[ print(utf8.nfcnormalize("áé")) ]])
run("tonumber-hex", [[ print(tonumber("e1", 16), string.char(tonumber("e1", 16))) ]])
