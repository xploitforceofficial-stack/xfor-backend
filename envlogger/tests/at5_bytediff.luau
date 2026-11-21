local fs = require("@lune/fs")
local luau = require("@lune/luau")

local source = fs.readFile("Samples/antitamperfound.lua")
source = string.gsub(source, "\r\n", "\n")

local i = string.find(source, "[==[", 1, true)
local j = string.find(source, "]==]", i, true)
local guarded = string.sub(source, i + 4, j - 1)

local env = { string = string, print = print, table = table, pcall = pcall }

local chunkSrc = "local guardedSource = [==[" .. guarded .. "]==]\nreturn guardedSource"

local fn = luau.load(chunkSrc, { environment = env, injectGlobals = false, debugName = "", codegenEnabled = true })
local inside = fn()

print("outside len:", #guarded, "inside len:", #inside)

local n = math.min(#guarded, #inside)
for k = 1, n do
	if string.byte(guarded, k) ~= string.byte(inside, k) then
		print("first diff at byte", k)
		print("outside ctx:", string.sub(guarded, math.max(1, k - 25), k + 25))
		print("inside  ctx:", string.sub(inside, math.max(1, k - 25), k + 25))
		break
	end
end
print("outside tail:", string.sub(guarded, -12):byte())
print("inside tail:", string.sub(inside, -12):byte())
print("outside head:", string.sub(guarded, 1, 12):byte())
print("inside head:", string.sub(inside, 1, 12):byte())
