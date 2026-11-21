local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local function run(label: string, code: string)
	local ok, res = pcall(Sandbox.run, code, { timeout = 30, maxNest = 1, name = "probe" })
	if not ok then
		print(label, "SANDBOX CRASH:", tostring(res):sub(1, 120))
		return
	end
	print(label, "| ok:", tostring(res.ok), "| err:", tostring(res.err):sub(1, 160))
end

run("hb-writable", [[
	local rs = game:GetService("RunService")
	local ok = pcall(function() rs.Heartbeat = nil end)
	print("write-ok:", tostring(ok)) -- expect false
	print("t-hb:", typeof(rs.Heartbeat))
	print("has-once:", tostring(type(rs.Heartbeat.Once)))
]])

run("conn-connect", [[
	local conn = game:GetService("RunService").Heartbeat:Connect(function() end)
	print("t-conn:", typeof(conn))
	conn:Disconnect()
]])

run("utf8-nan", [[
	local s = "héllo"
	local n = 0
	for g in utf8.graphemes(s) do n += 1 end
	print("graphemes:", n)
	local nan = 0/0
	print("nan==nan:", tostring(nan == nan))
	print("toc:", tostring(math.tointeger(nan)))
]])

run("enum-all", [[
	local e = Enum.AccessModifierType
	print("enum:", tostring(e))
	print("tp:", typeof(e))
]])

run("encoding", [[
	local es = game:GetService("EncodingService")
	print("es:", tostring(es ~= nil))
	local m = getmetatable(es) or {}
	for k in pairs(es) do print("key:", k) end
	local ok, r = pcall(function() return es:CompressZstd("hello") end)
	print("zstd:", tostring(ok), tostring(r):sub(1, 60))
]])

run("tween-goal", [[
	local ts = game:GetService("TweenService")
	local part = Instance.new("Part")
	local ok = pcall(function()
		return ts:Create(part, TweenInfo.new(1), {Position = "not-a-vector3"})
	end)
	print("bad-goal-ok:", tostring(ok)) -- expect false
	local ok2 = pcall(function()
		return ts:Create(part, TweenInfo.new(1), {Position = Vector3.new(1,2,3)})
	end)
	print("good-goal-ok:", tostring(ok2)) -- expect true
]])

run("getsecret", [[
	local hs = game:GetService("HttpService")
	local ok = pcall(function() return hs:GetSecret("bogus_key_123") end)
	print("secret-err-ok:", tostring(ok)) -- expect false
]])

run("hinge", [[
	local h = Instance.new("HingeConstraint")
	print("actuator:", tostring(h.ActuatorType), typeof(h.ActuatorType))
]])

run("setfenv-ls", [[
	local f = loadstring("return 42")
	local env = setfenv(f, {print=print})
	print("call:", tostring(f()))
]])
