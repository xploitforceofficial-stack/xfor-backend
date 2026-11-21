local fs = require("@lune/fs")

local source = fs.readFile("../envlogger/Samples/antitamperfound.lua")
source = string.gsub(source, "\r\n", "\n")
print("normalized size:", #source)

local i = string.find(source, "[==[", 1, true)
local j = string.find(source, "]==]", i, true)
local guarded = string.sub(source, i + 4, j - 1)
print("guarded len:", #guarded)

local function checksum(value: string): number
	local hash = 5381
	for i = 1, #value do
		hash = (hash * 33 + string.byte(value, 1 + i - 1)) % 4294967296
	end
	return hash
end

local h = checksum(guarded)
print("checksum:", h, "expect 4191847112", h == 4191847112)
