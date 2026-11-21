local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	print("gm:", debug.info(getmetatable, "slnaf"))
	print("sm:", debug.info(setmetatable, "slnaf"))
	print("tn:", debug.info(tonumber, "slnaf"))
	print("ts:", debug.info(tostring, "slnaf"))
	print("rawset:", debug.info(rawset, "slnaf"))
	print("rawget:", debug.info(rawget, "slnaf"))
	print("select:", debug.info(select, "slnaf"))
	print("xpcall:", debug.info(xpcall, "slnaf"))
	print("assert:", debug.info(assert, "slnaf"))
	print("error:", debug.info(error, "slnaf"))
	print("pcall:", debug.info(pcall, "slnaf"))
	print("type:", debug.info(type, "slnaf"))
	print("next:", debug.info(next, "slnaf"))
	print("getfenv:", debug.info(getfenv, "slnaf"))
	print("setfenv:", debug.info(setfenv, "slnaf"))
	print("typeof:", debug.info(typeof, "slnaf"))
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
