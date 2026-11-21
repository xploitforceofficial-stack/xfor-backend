local fs = require("@lune/fs")
local luau = require("@lune/luau")

local source = fs.readFile("tests/at5_ckprint.lua")
source = string.gsub(source, "\r\n", "\n")

local captured: { string } = {}
local function recPrint(...: any)
	local parts: { string } = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	captured[#captured + 1] = table.concat(parts, "\t")
end

local env: any = { print = recPrint :: any, string = string, table = table, math = math, pcall = pcall, error = error, loadstring = loadstring, setmetatable = setmetatable, getmetatable = getmetatable, type = type, tostring = tostring, select = select, next = next, rawget = rawget, rawset = rawset, rawequal = rawequal, ipairs = ipairs, pairs = pairs, assert = assert, tonumber = tonumber, unpack = unpack, coroutine = coroutine, task = task, buffer = buffer, bit32 = bit32, utf8 = utf8, os = os, debug = debug, typeof = typeof, game = game }

local fn = luau.load(source, {
	environment = env,
	injectGlobals = false,
	debugName = "",
	codegenEnabled = true,
})

local ok, err = pcall(fn)
print("ok:", ok, "err:", tostring(err):sub(1, 120))
for _, line in ipairs(captured) do
	print("out:", line)
end
