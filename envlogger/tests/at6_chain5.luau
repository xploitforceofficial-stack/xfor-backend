local fs = require("@lune/fs")
local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local cases = {
	'local h = game:GetService("CollectionService"):HasTag(p, "tag")',
	'game:GetService("TextService"):GetTextSize("t", 16)',
	'local x = game:GetService("RunService").Stepped',
	'local a = p:FindFirstChild("x"):FindFirstChild("y")',
	'local b = ({1,2})[1]',
	't[k]:Method():Other()',
	'local c = foo(function()\n\tbar:Baz()\nend)',
	'if x then\n\tp:Destroy()\nend',
	'local d = (getfenv()):WaitForChild("q")',
	'local e = a.b.c:Method()',
	'local f = s:gsub(".", "x"):upper()',
}
for _, case in ipairs(cases) do
	local out, err = SrcEdit.wrapSafeIndexing(case, Instrument.tokenize)
	local ok = true
	if out then
		local fn = loadstring(out)
		ok = fn ~= nil
	end
	print((ok and "OK  " or "BAD ") .. string.gsub(case, "\n", "\n"))
	if not ok or out == nil then print("   -> " .. tostring(out) .. " err=" .. tostring(err)) end
end
