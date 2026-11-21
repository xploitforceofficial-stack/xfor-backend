local fs = require("@lune/fs")

local source = fs.readFile("../Samples/PSU/v5/1.lua")
local tail = source:sub(1000532)
local full = "return function(...) " .. tail .. " end"

local fn, err = loadstring(full)
if not fn then
	print("load failed:", (err:gsub("\n", " ")))
	return
end
print("tail loads OK in Luau")

local function noop() return nil end

local env = {
	pcall = pcall,
	xpcall = xpcall,
	select = select,
	rawget = rawget,
	rawset = rawset,
	setmetatable = setmetatable,
	getmetatable = getmetatable,
	tonumber = tonumber,
	tostring = tostring,
	type = type,
	ipairs = ipairs,
	pairs = pairs,
	next = next,
	unpack = unpack,
	table = table,
	string = string,
	math = math,
	os = { time = function() return 0 end, clock = os.clock },
	tick = function() return 0 end,
	error = error,
	assert = assert,
	print = print,
	game = nil,
	script = nil,
	getfenv = function() return env end,
	setfenv = function() return nil end,
	_BIT = nil,
	bit32 = bit32,
	bit = bit,
}

setfenv(fn, env)

local ok, result = pcall(fn)
if ok then
	print("ran OK, result type:", type(result))
else
	print("runtime error:", tostring(result):sub(1, 300))
end
