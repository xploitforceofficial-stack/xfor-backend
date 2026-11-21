local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = [====[
local out = {}
local function log(s) out[#out+1] = s end
local function safeTypeof(v) local ok, t = pcall(typeof or type, v) return ok and t or type(v) end

-- 1. typeof of signals
log("typeof Heartbeat: " .. safeTypeof(game:GetService("RunService").Heartbeat))
log("typeof Stepped: " .. safeTypeof(game:GetService("RunService").Stepped))
log("typeof RenderStepped: " .. safeTypeof(game:GetService("RunService").RenderStepped))
log("typeof ServiceAdded: " .. safeTypeof(game.ServiceAdded))

-- 2. Heartbeat writable?
local ok2 = pcall(function() game:GetService("RunService").Heartbeat = nil end)
log("set Heartbeat=nil: " .. tostring(ok2))

-- 3. Once/Wait exist?
local hb = game:GetService("RunService").Heartbeat
log("type hb.Once: " .. type(hb.Once))
log("type hb.Wait: " .. type(hb.Wait))

-- 4. connections unique?
local a = game.ServiceAdded:Connect(function() end)
local b = game.ServiceAdded:Connect(function() end)
log("conn a~=b: " .. tostring(a ~= b))
log("typeof a: " .. safeTypeof(a))
a:Disconnect() b:Disconnect()

-- 5. typeof connection from Heartbeat
local conn = hb:Connect(function() end)
log("typeof hb conn: " .. safeTypeof(conn))
conn:Disconnect()

-- 6. Fire frame signals: does Heartbeat callback run?
local ran = false
local c2 = hb:Connect(function() ran = true end)
-- eunc uses task.wait to advance frames
task.wait()
log("hb fired after task.wait: " .. tostring(ran))
c2:Disconnect()

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
