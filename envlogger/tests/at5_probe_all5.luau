local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")
local source = fs.readFile("tests/at5_fixture_all.lua")
local result = Sandbox.run(source, { timeout = 180, maxExplored = 0 })
print("err:", result.err)
local fails, failcount = {}, 0
for _, o in ipairs(result.outputs or {}) do
	if o.text:find("^FAIL ") or o.text:find("\nFAIL ") then
		for line in o.text:gmatch("[^\n]+") do
			if line:find("^FAIL ") then
				fails[#fails + 1] = line
			end
		end
	end
	if o.text:find("FAILCOUNT") then
		for line in o.text:gmatch("[^\n]+") do
			if line:find("^FAILCOUNT") then
				failcount = tonumber((line:gsub("FAILCOUNT%s*", ""))) or failcount
			end
		end
	end
end
print("FAILCOUNT:", failcount)
for _, f in ipairs(fails) do
	print(f)
end
if failcount == 0 and #fails == 0 then
	print("ANTITAMPER BATTERY: FULLY BYPASSED")
end
