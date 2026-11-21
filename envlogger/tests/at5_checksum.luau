local fs = require("@lune/fs")
local luau = require("@lune/luau")

local source = fs.readFile("../envlogger/Samples/antitamperfound.lua")

local fn = luau.load(source, {
	environment = {},
	injectGlobals = false,
	debugName = "",
	codegenEnabled = true,
})

local ok, err = pcall(fn)
print("ok:", ok)
print("err:", tostring(err):sub(1, 200))
