local serde = require("@lune/serde")
local process = require("@lune/process")
local Sanitize = require("../src/core/sanitize")

local passed, failed = 0, 0
local failures: { string } = {}

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		failures[#failures + 1] = name .. (if detail then "  -> " .. detail else "")
	end
end

local function encodes(v: any): boolean
	return (pcall(serde.encode, "json", v)) == true
end

check("valid ascii untouched", Sanitize.utf8("hello world") == "hello world")
check("valid utf8 untouched", Sanitize.utf8("héllo - 世界") == "héllo - 世界")

local dirty = "`/\136&\188\164n\"Irr\6\29$"
check("invalid bytes made valid utf8", utf8.len(Sanitize.utf8(dirty)) ~= nil, Sanitize.utf8(dirty))
check("ascii preserved around bad bytes", string.find(Sanitize.utf8(dirty), "Irr", 1, true) ~= nil)
check("empty string", Sanitize.utf8("") == "")
check("all bad bytes", utf8.len(Sanitize.utf8("\255\254\253")) ~= nil)
check("trailing bad byte", utf8.len(Sanitize.utf8("ok\255")) ~= nil)
check("leading bad byte", utf8.len(Sanitize.utf8("\255ok")) ~= nil)

check("raw non-utf8 string breaks serde", not encodes({ err = dirty }))
check("jsonSafe rescues it", encodes(Sanitize.jsonSafe({ err = dirty })))
check("jsonSafe keeps scalars", (function()
	local out = Sanitize.jsonSafe({ n = 5, b = true, s = "ok" })
	return out.n == 5 and out.b == true and out.s == "ok"
end)())
check("jsonSafe recurses nested", encodes(Sanitize.jsonSafe({ a = { b = { c = dirty } }, list = { dirty, "clean" } })))
check("jsonSafe cleans non-utf8 keys", (function()
	local ok, encoded = pcall(serde.encode, "json", Sanitize.jsonSafe({ [dirty] = 1 }))
	return ok and type(encoded) == "string"
end)())
check("jsonSafe handles cycle", (function()
	local t: any = {}
	t.self = t
	return (pcall(Sanitize.jsonSafe, t)) == true
end)())

check("meta-like payload encodes", encodes(Sanitize.jsonSafe({
	version = "0.36.0",
	ok = false,
	error = dirty,
	outputs = { "score: 1234", dirty },
	elapsed = 0.18,
	inputBytes = 93377,
})))

print(string.format("\nsanitize: %d passed, %d failed", passed, failed))
if failed > 0 then
	for _, line in ipairs(failures) do
		print("  FAIL  " .. line)
	end
	process.exit(1)
end
