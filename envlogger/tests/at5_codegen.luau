local fs = require("@lune/fs")
local luau = require("@lune/luau")

local source = fs.readFile("Samples/antitamperfound.lua")
source = string.gsub(source, "\r\n", "\n")

local i = string.find(source, "[==[", 1, true)
local j = string.find(source, "]==]", i, true)
local guarded = string.sub(source, i + 4, j - 1)

local function checksum(value: string): number
	local hash = 5381
	for i = 1, #value do
		hash = (hash * 33 + string.byte(value, i)) % 4294967296
	end
	return hash
end

print("outside: len", #guarded, "ck", checksum(guarded))

local env = { string = string, print = print, pcall = pcall, error = error, loadstring = loadstring, setmetatable = setmetatable, getmetatable = getmetatable, type = type, tostring = tostring, select = select, next = next, rawget = rawget, rawset = rawset, rawequal = rawequal, ipairs = ipairs, pairs = pairs, assert = assert, tonumber = tonumber, table = table, math = math, coroutine = coroutine, task = task, buffer = buffer, bit32 = bit32, utf8 = utf8, os = os, debug = debug, typeof = typeof, game = game }

local chunkSrc = "local guardedSource = [==[" .. guarded .. "]==]\n"
	.. "local function checksum(value) local hash = 5381 for i = 1, #value do hash = (hash * 33 + string.byte(value, i)) % 4294967296 end return hash end\n"
	.. "return checksum(guardedSource), #guardedSource"

local fnOn = luau.load(chunkSrc, { environment = env, injectGlobals = false, debugName = "", codegenEnabled = true })
local ckOn, lenOn = fnOn()
print("inside codegen=on:  len", lenOn, "ck", ckOn)

local fnOff = luau.load(chunkSrc, { environment = env, injectGlobals = false, debugName = "", codegenEnabled = false })
local ckOff, lenOff = fnOff()
print("inside codegen=off: len", lenOff, "ck", ckOff)
