local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

_G.__FUHD_DBG_INFO = true

local result = Sandbox.run([[
	print("getfenv:", debug.info(getfenv, "sln"))
	print("setfenv:", debug.info(setfenv, "sln"))
	print("getmetatable:", debug.info(getmetatable, "sln"))
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
