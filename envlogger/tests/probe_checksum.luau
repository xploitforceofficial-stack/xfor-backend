local fs = require("@lune/fs")
local s = fs.readFile("Samples/antitamperfound.lua")
local i = string.find(s, "%[=%[%", 1, false)
print("bracket find pattern:", i)

local a = (string.find(s, "[==[", 1, true))
local b = (string.find(s, "]==]", a or 1, true))
print("open:", a, "close:", b)
local start = a + 4
if string.sub(s, start, start) == "\n" then start += 1 end
local content = string.sub(s, start, b - 1)
print("len:", #content)
local h = 5381
for k = 1, #content do
	h = (h * 33 + string.byte(content, k)) % 4294967296
end
print("luau checksum:", h)

local fn, err = loadstring(content, "G")
print("loads:", fn ~= nil, err)
