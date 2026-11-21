local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local cases = {
	'local h = game:GetService("CollectionService"):HasTag(p, "tag")',
	'game:GetService("TextService"):GetTextSize("t", 16)',
	'local x = game:GetService("RunService").Stepped',
	'foo:Bar("a"):Baz()',
}
for _, case in ipairs(cases) do
	local out, err = SrcEdit.wrapSafeIndexing(case, Instrument.tokenize)
	print("IN : " .. case)
	print("OUT: " .. tostring(out) .. "  err=" .. tostring(err))
	print()
end
