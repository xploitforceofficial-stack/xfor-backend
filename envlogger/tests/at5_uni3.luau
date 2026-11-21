local Sandbox = require("../src/core/sandbox")
local function run(label, body)
	local ok, res = pcall(Sandbox.run, body, { timeout = 30 })
	if not ok then print(label .. "| sandbox error: " .. tostring(res)) return end
	print(label .. "| ok=" .. tostring(res.ok) .. " err=" .. tostring(res.err))
	for _, e in ipairs(res.outputs or {}) do print("   OUT|" .. tostring(e.text)) end
end
run("char1", [[ print(utf8.char(97)) ]])
run("char2", [[ print(utf8.char(97, 98)) ]])
run("codepoint", [[ print(utf8.codepoint("abc", 1)) ]])
run("codes", [[ local a, b = utf8.codes("abc") print(type(a), tostring(b)) ]])
run("charpattern", [[ print(utf8.charpattern) ]])
