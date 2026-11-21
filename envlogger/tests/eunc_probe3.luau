local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = [====[
local out = {}
local function log(s) out[#out+1] = s end
local function safeTypeof(v) local ok, t = pcall(typeof or type, v) return ok and t or type(v) end

-- chained form
local hb1 = game:GetService("RunService").Heartbeat
log("chained hb1: " .. tostring(hb1))

-- local form
local rs = game:GetService("RunService")
local hb2 = rs.Heartbeat
log("local hb2: " .. tostring(hb2))

-- typeof both
log("typeof hb1: " .. safeTypeof(hb1))
log("typeof hb2: " .. safeTypeof(hb2))

-- service variable form is what eUNC uses:
-- local rs = getService("RunService"); rs.Heartbeat:Connect(...)
log("type hb2.Connect: " .. type(hb2.Connect))
log("type hb2.Once: " .. type(hb2.Once))
log("type hb2.Wait: " .. type(hb2.Wait))

local conn = hb2:Connect(function() end)
log("typeof conn: " .. safeTypeof(conn))
log("conn.Connected: " .. tostring(conn.Connected))
conn:Disconnect()

-- wait on heartbeat
local t0 = os.clock()
local dt = hb2:Wait()
log("Wait returned: " .. tostring(dt))

-- write test
local okW = pcall(function() rs.Heartbeat = nil end)
log("write Heartbeat=nil ok: " .. tostring(okW))

-- RunService signals typeof
log("typeof Stepped: " .. safeTypeof(rs.Stepped))
log("typeof RenderStepped: " .. safeTypeof(rs.RenderStepped))

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
