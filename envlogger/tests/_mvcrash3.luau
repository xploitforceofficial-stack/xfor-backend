local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")
local result = Sandbox.run(src, { timeout = 100, maxExplored = 0 })

local ds = result.decryptedStrings or {}
print("decrypted:", #ds)
for i = math.max(1, #ds - 25), #ds do
	local s = ds[i]
	if type(s) == "string" then
		print(i, string.format("%q", s:sub(1, 40)))
	end
end
