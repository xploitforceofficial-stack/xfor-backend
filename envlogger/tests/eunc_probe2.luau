local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = [====[
local out = {}
local function log(s) out[#out+1] = s end
local function safeTypeof(v) local ok, t = pcall(typeof or type, v) return ok and t or type(v) end

local rs = game:GetService("RunService")
log("rs type: " .. type(rs))
log("rs typeof: " .. safeTypeof(rs))
log("rs.ClassName: " .. tostring(rs.ClassName))

local hb = rs.Heartbeat
log("rs.Heartbeat: " .. tostring(hb))
log("rs.Heartbeat type: " .. type(hb))

-- dot vs GetService cache
local rs2 = game:GetService("RunService")
log("rs == rs2: " .. tostring(rs == rs2))

-- what about direct game.RunService?
log("game.RunService type: " .. type(game.RunService))
log("game.RunService == rs: " .. tostring(game.RunService == rs))

-- rawdump a few keys
for _, k in {"Heartbeat", "Stepped", "RenderStepped", "PreRender", "PreSimulation", "PostSimulation", "IsClient", "IsServer"} do
	log("  rs." .. k .. " = " .. type(rs[k]))
end

-- ServiceAdded on game
log("game.ServiceAdded: " .. type(game.ServiceAdded))
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
