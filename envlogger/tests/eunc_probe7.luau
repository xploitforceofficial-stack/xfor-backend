local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = [====[
local out = {}
local function log(s) out[#out+1] = s end

-- case 1: fresh loadstring then setfenv then call
local fn = loadstring("return foo")
log("type fn: " .. type(fn))
local env = { foo = 123 }
local ok = pcall(setfenv, fn, env)
log("setfenv ok: " .. tostring(ok))
local okCall, res = pcall(fn)
log("fn(): " .. tostring(res))

-- case 2: setfenv then call directly (no pcall)
local fn2 = loadstring("return bar")
setfenv(fn2, { bar = "iso" })
log("fn2(): " .. tostring(fn2()))

-- case 3: does getfenv(fn) see it?
local fn3 = loadstring("return baz")
setfenv(fn3, { baz = 9 })
local e = getfenv(fn3)
log("getfenv(fn3).baz: " .. tostring(type(e) == "table" and e.baz or "<no table>"))

print(table.concat(out, "\n"))
]====]

local ok, res = pcall(Sandbox.run, source, { timeout = 60, maxNest = 1 })
if not ok then
	print("SANDBOX CRASH:", res)
	return
end
print("ok:", res.ok, "err:", tostring(res.err):sub(1, 300))
if type(res.outputs) == "table" then
	for _, item in res.outputs do
		print(if type(item) == "table" then tostring(item.text or item[1]) else tostring(item))
	end
end
