local luau = require("@lune/luau")

local chunk = "return string.byte(\"A\")"
local fn = luau.load(chunk, {
	environment = {},
	injectGlobals = false,
	debugName = "",
	codegenEnabled = true,
})
local ok, res = pcall(fn)
print("empty env ok:", ok, "res:", tostring(res))

local env = setmetatable({}, { __index = _G })
local fn2 = luau.load(chunk, {
	environment = env,
	injectGlobals = false,
	debugName = "",
	codegenEnabled = true,
})
local ok2, res2 = pcall(fn2)
print("meta env ok:", ok2, "res:", tostring(res2))
