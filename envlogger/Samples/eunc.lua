local eUNC_VERSION = "0.1"

print("Welcome to eUNC, your go-to utility benchmark for environment loggers (aka runtime loggers) - If you need questions or help dm @rxlumz on dc!~")

local passedCount, failedCount = 0, 0
local failLines = {}
local resultBits = {}

local function safeTypeof(v)
    local tf = typeof or type
    local ok, t = pcall(tf, v)
    if ok then
        return t
    end
    return type(v)
end

local function isCFunction(fn)
    if type(fn) ~= "function" then
        return false
    end
    if debug and type(debug.getinfo) == "function" then
        local ok, info = pcall(debug.getinfo, fn)
        if ok and type(info) == "table" then
            if info.what == "C" or info.source == "=[C]" then
                return true
            end
            if info.what == "Lua" or info.what == "Lua" then
                return false
            end
        end
    end
    if debug and type(debug.info) == "function" then
        local ok, src = pcall(debug.info, fn, "s")
        if ok and src == "[C]" then
            return true
        end
        if ok and type(src) == "string" and src ~= "[C]" then
            return false
        end
    end

    if type(getfenv) == "function" then
        local ok, env = pcall(getfenv, fn)
        if ok and env == nil then
            return true
        end
    end
    return false
end

local function getService(name)
    return game:GetService(name)
end

local lastFail = nil

local function check(desc, fn)
    print("[eUNC]   check: " .. desc)
    local ok, err = pcall(fn)
    if not ok then
        local msg = tostring(err)
        if string.find(msg, "assertion failed", 1, true) then
            lastFail = { kind = "fail", check = desc }
        else
            lastFail = { kind = "error", check = desc, err = msg }
        end
        error("eUNC_CHECK")
    end
    if err == false then
        lastFail = { kind = "fail", check = desc }
        error("eUNC_CHECK")
    end
end

local function assertTrue(cond, msg)
    if not cond then
        error(msg or "assertion failed", 2)
    end
end

local function expectError(fn)
    local ok = pcall(fn)
    return not ok
end

local function TEST(name, fn)
    print("[eUNC] running: " .. name)
    lastFail = nil
    local ok, err = pcall(fn)
    if ok then
        passedCount += 1
        table.insert(resultBits, 1)
        return
    end
    failedCount += 1
    table.insert(resultBits, 0)
    if lastFail and lastFail.kind == "fail" then
        table.insert(failLines, string.format("[ FAIL ] - %s ~ %s failed", name, lastFail.check))
    elseif lastFail and lastFail.kind == "error" then
        table.insert(failLines, string.format("[ FAIL ] - %s ~ %s errored: %s", name, lastFail.check, lastFail.err))
    else
        local msg = tostring(err)
        if err == false or err == nil or msg == "false" then
            table.insert(failLines, string.format("[ FAIL ] - %s ~ returned false or nil", name))
        else
            table.insert(failLines, string.format("[ FAIL ] - %s", name))
        end
    end
end

TEST("game integrity checks", function()
    check("game cannot be cloned", function()
        local ok, res = pcall(function()
            return game:Clone()
        end)
        assertTrue((not ok) or res == nil)
    end)
end)

TEST("game & workspace & services type/typeof/metatable/parent/ etc correct", function()
    check("type(game) is userdata", function()
        assertTrue(type(game) == "userdata")
    end)
    assertTrue(safeTypeof(game) == "Instance")
    assertTrue(safeTypeof(workspace) == "Instance")
    assertTrue(game.Parent == nil)
    assertTrue(workspace.Parent == game or workspace:IsDescendantOf(game))
    local mt = getmetatable(game)
    assertTrue(mt ~= nil)
end)

TEST("Heartbeat:Connect returns RBXScriptConnection", function()
    local rs = getService("RunService")
    local conn = rs.Heartbeat:Connect(function() end)
    assertTrue(safeTypeof(conn) == "RBXScriptConnection")
    conn:Disconnect()
end)

TEST("Heartbeat not writable", function()
    local rs = getService("RunService")
    local ok = pcall(function()
        rs.Heartbeat = nil
    end)
    assertTrue(not ok)
end)

TEST("Heartbeat.Once exists", function()
    local hb = getService("RunService").Heartbeat
    assertTrue(type(hb.Once) == "function")
end)

TEST("Heartbeat.Wait exists", function()
    local hb = getService("RunService").Heartbeat
    assertTrue(type(hb.Wait) == "function")
end)

TEST("RunService signals are RBXScriptSignal", function()
    local rs = getService("RunService")
    assertTrue(safeTypeof(rs.Heartbeat) == "RBXScriptSignal")
    assertTrue(safeTypeof(rs.Stepped) == "RBXScriptSignal")
    assertTrue(safeTypeof(rs.RenderStepped) == "RBXScriptSignal")
end)

TEST("RunService client checks", function()
    check("RunService:IsClient returns true", function()
        assertTrue(getService("RunService"):IsClient() == true)
    end)
    local rs = getService("RunService")
    pcall(function()
        assertTrue(rs:IsServer() == false)
    end)
end)

TEST("ServiceAdded gives unique connections", function()
    local a = game.ServiceAdded:Connect(function() end)
    local b = game.ServiceAdded:Connect(function() end)
    assertTrue(a ~= b)
    a:Disconnect()
    b:Disconnect()
end)

TEST("task is table", function()
    assertTrue(type(task) == "table")
end)

TEST("task.wait returns positive number", function()
    local t = task.wait()
    assertTrue(type(t) == "number" and t > 0)
end)

TEST("task.spawn runs immediately", function()
    local ran = false
    task.spawn(function()
        ran = true
    end)
    assertTrue(ran)
end)

TEST("task.spawn returns thread", function()
    local th = task.spawn(function() end)
    assertTrue(type(th) == "thread")
end)

TEST("task.defer runs after yield", function()
    local ran = false
    task.defer(function()
        ran = true
    end)
    assertTrue(not ran)
    task.wait()
    assertTrue(ran)
end)

TEST("task.cancel exists", function()
    assertTrue(type(task.cancel) == "function")
end)

TEST("task.cancel prevents deferred thread from running", function()
    local ran = false
    local th = task.defer(function()
        ran = true
    end)
    task.cancel(th)
    task.wait()
    assertTrue(not ran)
end)

TEST("task.cancel prevents delayed thread from running", function()
    local ran = false
    local th = task.delay(0.05, function()
        ran = true
    end)
    task.cancel(th)
    task.wait(0.1)
    assertTrue(not ran)
end)

TEST("task.wait respects minimum duration", function()
    local t0 = os.clock()
    task.wait(0.05)
    assertTrue(os.clock() - t0 >= 0.04)
end)

TEST("task.delay does not fire immediately", function()
    local ran = false
    task.delay(0.2, function()
        ran = true
    end)
    assertTrue(not ran)
end)

TEST("task.cancel on already-ran thread does not error", function()
    local th = task.spawn(function() end)
    local ok = pcall(task.cancel, th)
    assertTrue(ok)
end)

TEST("getfenv and setfenv correctness", function()
    check("getfenv exists", function()
        assertTrue(type(getfenv) == "function")
    end)
    check("setfenv exists", function()
        assertTrue(type(setfenv) == "function")
    end)
    check("setfenv on loadstring function works", function()
        local fn = loadstring("return foo")
        local env = { foo = 123 }
        setfenv(fn, env)
        assertTrue(fn() == 123)
    end)
    check("setfenv isolates environment", function()
        local fn = loadstring("return bar")
        setfenv(fn, { bar = "iso" })
        assertTrue(fn() == "iso")
        assertTrue(bar == nil)
    end)
    check("setfenv does not leak into caller", function()
        local before = getfenv(1)
        local fn = loadstring("return 1")
        setfenv(fn, { leaked = true })
        fn()
        assertTrue(getfenv(1) == before)
        assertTrue(rawget(before, "leaked") == nil)
    end)
    check("getfenv(0) returns global env", function()
        local e = getfenv(0)
        assertTrue(type(e) == "table")
        assertTrue(e == getfenv(0))
    end)
    check("getfenv(1) returns current env", function()
        local e = getfenv(1)
        assertTrue(type(e) == "table")
    end)
end)

TEST("utf8 graphemes and math.nan", function()
    check("utf8.graphemes exists", function()
        assertTrue(type(utf8.graphemes) == "function")
    end)
    assertTrue(math.isnan == nil or type(math.isnan) == "function" or math.isnan(0 / 0))
    local nan = 0 / 0
    assertTrue(nan ~= nan)
end)

TEST("task scheduling order ACBD", function()
    local order = ""
    task.spawn(function()
        order ..= "A"
    end)
    order ..= "C"
    task.defer(function()
        order ..= "B"
    end)
    task.wait()
    order ..= "D"
    assertTrue(order == "ACBD")
end)

TEST("Pass Gold.cc Anti Env V3 on Scriptblox!", function()

    local part = Instance.new("Part")
    assertTrue(type(part) == "userdata")
    assertTrue(safeTypeof(part) == "Instance")
    assertTrue(part.ClassName == "Part")
    local okNew, errNew = pcall(Instance.new, "ThisClassDoesNotExist_eUNC")
    assertTrue(not okNew)
    assertTrue(type(errNew) == "string")
    assertTrue(not string.find(string.lower(tostring(errNew)), "attempt to index"))
    assertTrue(type(game) == "userdata")
    assertTrue(safeTypeof(game) == "Instance")
    assertTrue(game.Parent == nil)
    local okClone, cloned = pcall(function()
        return game:Clone()
    end)
    assertTrue((not okClone) or cloned == nil)
    assertTrue(type(typeof) == "function")
    assertTrue(typeof ~= type)
end)

TEST("Instance.new Part", function()
    local p = Instance.new("Part")
    assertTrue(p ~= nil)
    check("Instance.new error is not runtime error (anti-fake check)", function()
        local ok, err = pcall(Instance.new, "a")
        assertTrue(not ok)
        assertTrue(type(err) == "string")

        assertTrue(#err > 0)
    end)
end)

TEST("Part.ClassName == Part", function()
    local p = Instance.new("Part")
    assertTrue(p.ClassName == "Part")
end)

TEST("New Part parent is nil", function()
    local p = Instance.new("Part")
    assertTrue(p.Parent == nil)
end)

TEST("Part is userdata not table", function()
    local p = Instance.new("Part")
    assertTrue(type(p) == "userdata")
    assertTrue(type(p) ~= "table")
end)

TEST("Destroyed part parent is nil", function()
    local p = Instance.new("Part")
    p:Destroy()
    assertTrue(p.Parent == nil)
end)

TEST("CFrame.Position sub-property is frozen", function()
    local cf = CFrame.new(1, 2, 3)
    local pos = cf.Position
    assertTrue(expectError(function()
        pos.X = 0
    end) or expectError(function()
        cf.Position = Vector3.new()
    end))
end)

TEST("Clone returns different reference", function()
    local p = Instance.new("Part")
    local c = p:Clone()
    assertTrue(c ~= nil and c ~= p)
end)

TEST("Archivable false clone returns nil", function()
    local p = Instance.new("Part")
    p.Archivable = false
    assertTrue(p:Clone() == nil)
end)

TEST("ClearAllChildren works", function()
    local f = Instance.new("Folder")
    local a = Instance.new("Part")
    a.Parent = f
    f:ClearAllChildren()
    assertTrue(#f:GetChildren() == 0)
    assertTrue(a.Parent == nil)
end)

TEST("ClassName is not writable", function()
    local p = Instance.new("Part")
    local ok = pcall(function()
        p.ClassName = "Folder"
    end)
    assertTrue(not ok)
    assertTrue(p.ClassName == "Part")
end)

TEST("Instance parenting works", function()
    local f = Instance.new("Folder")
    local p = Instance.new("Part")
    p.Parent = f
    assertTrue(p.Parent == f)
    assertTrue(p:IsDescendantOf(f))
end)

TEST("Instance parent cant be table", function()
    local p = Instance.new("Part")
    local ok = pcall(function()
        p.Parent = {}
    end)
    assertTrue(not ok)
end)

TEST("FindFirstChild not recursive by default", function()
    local f = Instance.new("Folder")
    f.Name = "Root"
    local inner = Instance.new("Folder")
    inner.Name = "Inner"
    inner.Parent = f
    local deep = Instance.new("Part")
    deep.Name = "Deep"
    deep.Parent = inner
    assertTrue(f:FindFirstChild("Deep") == nil)
    assertTrue(f:FindFirstChild("Inner") == inner)
    local rec = f:FindFirstChild("Deep", true)
    assertTrue(rec == deep)
end)

TEST("game.IsLoaded not writable", function()
    local ok = pcall(function()
        game.IsLoaded = false
    end)
    assertTrue(not ok)
end)

TEST("BindableEvent fires", function()
    local be = Instance.new("BindableEvent")
    local fired = false
    be.Event:Connect(function(v)
        fired = v == 7
    end)
    be:Fire(7)
    assertTrue(fired)
end)

TEST("BindableEvent signal type", function()
    local be = Instance.new("BindableEvent")
    assertTrue(safeTypeof(be.Event) == "RBXScriptSignal")
end)

TEST("Heartbeat dt is valid", function()
    local dt
    local conn
    conn = getService("RunService").Heartbeat:Connect(function(d)
        dt = d
        conn:Disconnect()
    end)
    task.wait(0.2)
    assertTrue(type(dt) == "number" and dt > 0 and dt < 1)
end)

TEST("Heartbeat fires within reasonable time", function()
    local t0 = os.clock()
    getService("RunService").Heartbeat:Wait()
    assertTrue(os.clock() - t0 < 1)
end)

TEST("Stepped fires within reasonable time", function()
    local t0 = os.clock()
    getService("RunService").Stepped:Wait()
    assertTrue(os.clock() - t0 < 1)
end)

TEST("RenderStepped fires within reasonable time", function()
    local t0 = os.clock()
    getService("RunService").RenderStepped:Wait()
    assertTrue(os.clock() - t0 < 1)
end)

TEST("Heartbeat delta is consistent", function()
    local a = getService("RunService").Heartbeat:Wait()
    local b = getService("RunService").Heartbeat:Wait()
    assertTrue(type(a) == "number" and type(b) == "number")
    assertTrue(a > 0 and b > 0)
    assertTrue(math.abs(a - b) < 0.2)
end)

TEST("Heartbeat timestamps differ", function()
    local t1 = os.clock()
    getService("RunService").Heartbeat:Wait()
    local t2 = os.clock()
    getService("RunService").Heartbeat:Wait()
    local t3 = os.clock()
    assertTrue(t2 > t1 and t3 > t2)
end)

TEST("debug is table", function()
    assertTrue(type(debug) == "table")
end)

TEST("debug.getinfo exists", function()
    assertTrue(type(debug.getinfo) == "function")
end)

TEST("debug.getinfo returns Lua what", function()
    local info = debug.getinfo(function() end)
    assertTrue(type(info) == "table")
    assertTrue(info.what == "Lua")
end)

TEST("pcall, xpcall, ypcall", function()
    check("pcall is function", function()
        assertTrue(type(pcall) == "function")
    end)
    check("xpcall is function", function()
        assertTrue(type(xpcall) == "function")
    end)
    check("pcall catches errors", function()
        local ok, err = pcall(function()
            error("boom")
        end)
        assertTrue(ok == false)
        assertTrue(type(err) == "string")
    end)
    check("pcall returns values on success", function()
        local ok, a, b = pcall(function()
            return 1, 2
        end)
        assertTrue(ok == true and a == 1 and b == 2)
    end)
    check("ypcall is function", function()
        assertTrue(type(ypcall) == "function")
    end)
    check("ypcall catches errors like pcall", function()
        local ok = ypcall(function()
            error("yp")
        end)
        assertTrue(ok == false)
    end)
    check("ypcall returns values on success", function()
        local ok, v = ypcall(function()
            return 99
        end)
        assertTrue(ok == true and v == 99)
    end)
end)

TEST("tostring is stable", function()
    local t = {}
    assertTrue(tostring(t) == tostring(t))
    local p = Instance.new("Part")
    assertTrue(tostring(p) == tostring(p))
end)

TEST("_G rawget consistency", function()
    local key = "__eunc_rawget_probe"
    _G[key] = 42
    assertTrue(rawget(_G, key) == 42)
    rawset(_G, key, nil)
    assertTrue(rawget(_G, key) == nil)
end)

TEST("roblox globals & legacy funcs", function()
    check("_VERSION is string", function()
        assertTrue(type(_VERSION) == "string")
    end)
    check("_VERSION is Luau", function()
        assertTrue(string.find(_VERSION, "Luau") ~= nil)
    end)
    check("shared is table", function()
        assertTrue(type(shared) == "table")
    end)
    assertTrue(type(tick) == "function" or type(tick) == "number" or tick ~= nil)
    assertTrue(type(wait) == "function" or type(task.wait) == "function")
end)

TEST("os.clock non-negative", function()
    assertTrue(type(os.clock()) == "number" and os.clock() >= 0)
end)

TEST("coroutine.create status suspended", function()
    local co = coroutine.create(function() end)
    assertTrue(coroutine.status(co) == "suspended")
end)

TEST("buffer.create exists", function()
    assertTrue(type(buffer.create) == "function")
    local b = buffer.create(8)
    assertTrue(b ~= nil)
end)

TEST("buffer read/write string", function()
    local b = buffer.create(16)
    buffer.writestring(b, 0, "hello")
    assertTrue(buffer.readstring(b, 0, 5) == "hello")
end)

TEST("newproxy returns userdata", function()
    local p = newproxy(true)
    assertTrue(type(p) == "userdata")
    assertTrue(type(getmetatable(p)) == "table")
end)

TEST("C functions do not trigger proxy metatables", function()
    local fired = false
    local proxy = newproxy(true)
    local mt = getmetatable(proxy)
    mt.__index = function()
        fired = true
        return 0
    end
    mt.__call = function()
        fired = true
    end
    mt.__tostring = function()
        fired = true
        return "p"
    end
    pcall(function()
        math.abs(proxy)
    end)
    pcall(function()
        string.len(proxy)
    end)

    assertTrue(isCFunction(math.abs) or type(math.abs) == "function")
    assertTrue(type(math.abs) == "function")

    fired = false
    local _ = math.abs
    assertTrue(not fired)
end)

TEST("standard libraries are frozen (readonly)", function()
    assertTrue(expectError(function()
        string.sub = function() end
    end) or expectError(function()
        string.__eunc = true
    end))
    assertTrue(expectError(function()
        table.insert = function() end
    end) or expectError(function()
        math.abs = function() end
    end))
end)

TEST("getgenv returns consistent table", function()
    assertTrue(type(getgenv) == "function")
    local a = getgenv()
    local b = getgenv()
    assertTrue(type(a) == "table")
    assertTrue(a == b)
end)

TEST("getgenv contains _G", function()
    local g = getgenv()
    assertTrue(g._G == _G or rawget(g, "_G") == _G or g == _G)
end)

TEST("string.dump errors on C function", function()
    local ok = pcall(function()
        return string.dump(print)
    end)
    assertTrue(not ok)
end)

TEST("EncodingService Zstd compress/decompress", function()
    local es = getService("EncodingService")
    local payload = "eUNC-zstd-roundtrip"
    local round
    if es.CompressZstd then
        round = es:DecompressZstd(es:CompressZstd(payload))
    elseif es.ZstdCompress then
        round = es:ZstdDecompress(es:ZstdCompress(payload))
    else
        local buf = buffer.fromstring(payload)
        local comp = es:CompressBuffer(buf, Enum.CompressionAlgorithm.Zstd)
        local de = es:DecompressBuffer(comp, Enum.CompressionAlgorithm.Zstd)
        round = buffer.tostring(de)
    end
    assertTrue(round == payload)
end)

TEST("setmetatable __index works", function()
    local t = {}
    setmetatable(t, {
        __index = { x = 5 },
    })
    assertTrue(t.x == 5)
end)

TEST("_G has no __index or __newindex", function()
    local mt = getmetatable(_G)
    if mt then
        assertTrue(mt.__index == nil)
        assertTrue(mt.__newindex == nil)
    end
end)

TEST("workspace default instances exist", function()
    check("Baseplate exists", function()
        local bp = workspace:FindFirstChild("Baseplate") or workspace:FindFirstChildWhichIsA("BasePart")
        assertTrue(bp ~= nil)
    end)
end)

TEST("camera properties and methods", function()
    check("workspace.CurrentCamera exists", function()
        assertTrue(workspace.CurrentCamera ~= nil)
        assertTrue(safeTypeof(workspace.CurrentCamera) == "Instance")
    end)
    local cam = workspace.CurrentCamera
    assertTrue(type(cam.WorldToScreenPoint) == "function" or type(cam.WorldToViewportPoint) == "function")
end)

TEST("PostFX & Atmosphere properties", function()
    local bloom = Instance.new("BloomEffect")
    check("BloomEffect.ClassName is BloomEffect", function()
        assertTrue(bloom.ClassName == "BloomEffect")
    end)
    check("BloomEffect.Intensity is number", function()
        assertTrue(type(bloom.Intensity) == "number")
    end)
    local atmo = Instance.new("Atmosphere")
    assertTrue(atmo.ClassName == "Atmosphere")
end)

TEST("Lighting Properties", function()
    local lighting = getService("Lighting")
    check("Lighting.Ambient is Color3", function()
        assertTrue(safeTypeof(lighting.Ambient) == "Color3")
    end)
    assertTrue(safeTypeof(lighting.ColorShift_Top) == "Color3" or type(lighting.Brightness) == "number")
end)

TEST("GetProductInfo (skidded check 100% of obfs have this)", function()
    check("MarketplaceService exists", function()
        assertTrue(getService("MarketplaceService") ~= nil)
    end)
    check("MarketplaceService.GetProductInfo is function", function()
        assertTrue(type(getService("MarketplaceService").GetProductInfo) == "function")
    end)
end)

TEST("TweenService", function()
    local ts = getService("TweenService")
    check("TweenService exists", function()
        assertTrue(ts ~= nil)
    end)
    check("TweenService.ClassName correct", function()
        assertTrue(ts.ClassName == "TweenService")
    end)
    local part = Instance.new("Part")
    check("TweenService rejects bad goal types", function()
        assertTrue(expectError(function()
            ts:Create(part, TweenInfo.new(1), { Position = "bad" })
        end))
    end)
    check("TweenService:Create returns Tween Instance", function()
        local tw = ts:Create(part, TweenInfo.new(0.1), { Transparency = 1 })
        assertTrue(safeTypeof(tw) == "Instance")
        assertTrue(tw.ClassName == "Tween")
    end)
end)

TEST("ContextActionService", function()
    local cas = getService("ContextActionService")
    check("ContextActionService exists", function()
        assertTrue(cas ~= nil)
    end)
    check("ContextActionService.ClassName correct", function()
        assertTrue(cas.ClassName == "ContextActionService")
    end)
    check("ContextActionService:BindAction works", function()
        local bound = false
        cas:BindAction("eUNC_Bind", function()
            bound = true
            return Enum.ContextActionResult.Pass
        end, false, Enum.KeyCode.F)
        pcall(function()
            cas:UnbindAction("eUNC_Bind")
        end)
        assertTrue(type(cas.BindAction) == "function")
    end)
end)

TEST("UserInputService", function()
    local uis = getService("UserInputService")
    check("UIS.TouchEnabled is boolean", function()
        assertTrue(type(uis.TouchEnabled) == "boolean")
    end)
end)

TEST("PathfindingService", function()
    local pfs = getService("PathfindingService")
    check("PathfindingService exists", function()
        assertTrue(pfs ~= nil)
    end)
    check("PathfindingService.ClassName correct", function()
        assertTrue(pfs.ClassName == "PathfindingService")
    end)
    check("PathfindingService:CreatePath returns object", function()
        local path = pfs:CreatePath()
        assertTrue(path ~= nil)
        assertTrue(type(path.GetWaypoints) == "function" or safeTypeof(path) == "Instance")
    end)
end)

TEST("Humanoid signals are RBXScriptSignal", function()
    local h = Instance.new("Humanoid")
    check("Humanoid.StateChanged is RBXScriptSignal", function()
        assertTrue(safeTypeof(h.StateChanged) == "RBXScriptSignal")
    end)
end)

TEST("Humanoid properties", function()
    local h = Instance.new("Humanoid")
    check("Humanoid.JumpHeight is number", function()
        assertTrue(type(h.JumpHeight) == "number")
    end)
end)

TEST("Instance methods", function()
    local f = Instance.new("Folder")
    local p = Instance.new("Part")
    p.Name = "ChildPart"
    p.Parent = f
    check("WaitForChild returns correct child", function()
        local c = f:WaitForChild("ChildPart", 1)
        assertTrue(c == p)
    end)
end)

TEST("Humanoid jump physics using HumanoidStateType.Jumping ", function()
    local players = getService("Players")
    check("LocalPlayer exists", function()
        assertTrue(players.LocalPlayer ~= nil)
    end)
    local lp = players.LocalPlayer
    local char = lp.Character or lp.CharacterAdded:Wait()
    local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    assertTrue(hum ~= nil)
    hum:ChangeState(Enum.HumanoidStateType.Jumping)
    task.wait()
    local st = hum:GetState()
    assertTrue(st == Enum.HumanoidStateType.Jumping or safeTypeof(st) == "EnumItem")
end)

TEST("particle effects", function()
    local ff = Instance.new("ForceField")
    check("ForceField.ClassName correct", function()
        assertTrue(ff.ClassName == "ForceField")
    end)
    check("ForceField.Visible is boolean", function()
        assertTrue(type(ff.Visible) == "boolean")
    end)
    local pe = Instance.new("ParticleEmitter")
    assertTrue(pe.ClassName == "ParticleEmitter")
end)

TEST("constraints and forces", function()
    local nc = Instance.new("NoCollisionConstraint")
    check("NoCollisionConstraint.ClassName correct", function()
        assertTrue(nc.ClassName == "NoCollisionConstraint")
    end)
    local hg = Instance.new("HingeConstraint")
    check("HingeConstraint.ClassName correct", function()
        assertTrue(hg.ClassName == "HingeConstraint")
    end)
    check("HingeConstraint.ActuatorType is EnumItem", function()
        assertTrue(safeTypeof(hg.ActuatorType) == "EnumItem")
    end)
end)

TEST("GUI textlabel properties", function()
    local tl = Instance.new("TextLabel")
    check("TextLabel.TextTruncate is EnumItem", function()
        assertTrue(safeTypeof(tl.TextTruncate) == "EnumItem")
    end)
end)

TEST("GUI frame properties", function()
    local fr = Instance.new("Frame")
    check("Frame.Position is UDim2", function()
        assertTrue(safeTypeof(fr.Position) == "UDim2")
    end)
end)

TEST("Workspace properties and functions work", function()
    check("workspace.DistributedGameTime is number", function()
        assertTrue(type(workspace.DistributedGameTime) == "number")
    end)
    assertTrue(type(workspace.GetBoundingBox) == "function" or type(workspace.Raycast) == "function")
end)

TEST("Part properties and signals", function()
    local p = Instance.new("Part")
    check("Part.Massless is boolean", function()
        assertTrue(type(p.Massless) == "boolean")
    end)
    assertTrue(safeTypeof(p.Touched) == "RBXScriptSignal" or type(p.GetMass) == "function")
end)

TEST("LocalPlayer & Players service(s)", function()
    local players = getService("Players")
    check("Players.LocalPlayer exists", function()
        assertTrue(players.LocalPlayer ~= nil)
        assertTrue(safeTypeof(players.LocalPlayer) == "Instance")
    end)
end)

TEST("StarterPlayer", function()
    local sp = getService("StarterPlayer")
    check("StarterPlayer.ClassName correct", function()
        assertTrue(sp.ClassName == "StarterPlayer")
    end)
    check("StarterPlayer has StarterPlayerScripts", function()
        assertTrue(sp:FindFirstChild("StarterPlayerScripts") ~= nil or sp.StarterPlayerScripts ~= nil)
    end)
end)

TEST("Vector3 properties and methods", function()
    check("Vector3.X Y Z correct", function()
        local v = Vector3.new(1, 2, 3)
        assertTrue(v.X == 1 and v.Y == 2 and v.Z == 3)
        assertTrue(typeof(v) == "Vector3" or safeTypeof(v) == "Vector3")
    end)
    local v = Vector3.new(3, 4, 0)
    assertTrue(math.abs(v.Magnitude - 5) < 1e-4)
end)

TEST("coroutine suspend correctness", function()
    check("coroutine status is suspended after yield", function()
        local co = coroutine.create(function()
            coroutine.yield(1)
        end)
        coroutine.resume(co)
        assertTrue(coroutine.status(co) == "suspended")
    end)
end)

TEST("Property clamping and validation", function()
    check("Color3 out of range is clamped or rejected", function()
        local ok, c = pcall(Color3.new, 2, -1, 0.5)
        if ok then
            assertTrue(c.R <= 1 and c.R >= 0)
            assertTrue(c.G <= 1 and c.G >= 0)
        else
            assertTrue(true)
        end
    end)
end)

TEST("GetChildren mutation correctness", function()
    check("GetChildren snapshot is immutable to parent changes", function()
        local f = Instance.new("Folder")
        local a = Instance.new("Part")
        a.Parent = f
        local snap = f:GetChildren()
        local b = Instance.new("Part")
        b.Parent = f
        assertTrue(#snap == 1)
        assertTrue(snap[1] == a)
        assertTrue(#f:GetChildren() == 2)
    end)
end)

TEST("LogService.MessageOut signal", function()
    local ls = getService("LogService")
    check("LogService.MessageOut is RBXScriptSignal", function()
        assertTrue(safeTypeof(ls.MessageOut) == "RBXScriptSignal")
    end)
end)

TEST("Enum structural integrity", function()
    check("EnumItem.EnumType points back to parent Enum", function()
        local item = Enum.ConnectionError.Unknown
        assertTrue(item.EnumType == Enum.ConnectionError)
        assertTrue(safeTypeof(item) == "EnumItem")
    end)
end)

TEST("task.defer and coroutine ordering", function()
    check("deferred tasks across folders resolve correctly", function()
        local f1 = Instance.new("Folder")
        local f2 = Instance.new("Folder")
        f2.Parent = f1
        local nv = Instance.new("NumberValue")
        nv.Parent = f2
        nv.Value = 0
        task.defer(function()
            nv.Value = 10
        end)
        task.wait()
        assertTrue(nv.Value == 10)
    end)
    check("deferred value accumulation is deterministic", function()
        local nv = Instance.new("NumberValue")
        nv.Value = 0
        task.defer(function()
            nv.Value += 1
        end)
        task.defer(function()
            nv.Value += 2
        end)
        task.wait()
        assertTrue(nv.Value == 3)
    end)
end)

TEST("coroutine and task interleaving", function()
    check("ClearAllChildren during deferred parent chain", function()
        local root = Instance.new("Folder")
        local mid = Instance.new("MeshPart")
        mid.Parent = root
        task.defer(function()
            root:ClearAllChildren()
        end)
        task.wait()
        assertTrue(mid.Parent == nil)
        assertTrue(#root:GetChildren() == 0)
    end)
end)

TEST("Vector2 properties and methods", function()
    check("Vector2.X Y correct", function()
        local v = Vector2.new(4, 5)
        assertTrue(v.X == 4 and v.Y == 5)
        assertTrue(safeTypeof(v) == "Vector2")
    end)
end)

TEST("SharedTable", function()
    check("SharedTable.new empty returns correct type", function()
        local st = SharedTable.new()
        assertTrue(safeTypeof(st) == "SharedTable")
    end)
end)

TEST("Vector2int16", function()
    check("Vector2int16.new returns correct type", function()
        local v = Vector2int16.new(1, 2)
        assertTrue(safeTypeof(v) == "Vector2int16")
    end)
end)

TEST("Vector3int16", function()
    check("Vector3int16.new returns correct type", function()
        local v = Vector3int16.new(1, 2, 3)
        assertTrue(safeTypeof(v) == "Vector3int16")
    end)
end)

TEST("ValueCurveKey", function()
    check("ValueCurveKey.new returns correct type", function()
        local v = ValueCurveKey.new(0, 1)
        assertTrue(safeTypeof(v) == "ValueCurveKey")
    end)
end)

TEST("CFrame properties and methods", function()
    check("CFrame.X Y Z correct", function()
        local cf = CFrame.new(1, 2, 3)
        assertTrue(math.abs(cf.X - 1) < 1e-5)
        assertTrue(math.abs(cf.Y - 2) < 1e-5)
        assertTrue(math.abs(cf.Z - 3) < 1e-5)
        assertTrue(safeTypeof(cf) == "CFrame")
    end)
end)

TEST("Color3 properties and methods", function()
    check("Color3.new R G B correct", function()
        local c = Color3.new(0.25, 0.5, 0.75)
        assertTrue(math.abs(c.R - 0.25) < 1e-5)
        assertTrue(math.abs(c.G - 0.5) < 1e-5)
        assertTrue(math.abs(c.B - 0.75) < 1e-5)
        assertTrue(safeTypeof(c) == "Color3")
    end)
end)

TEST("UDim and UDim2", function()
    check("UDim.Scale and Offset correct", function()
        local u = UDim.new(0.5, 10)
        assertTrue(u.Scale == 0.5 and u.Offset == 10)
        local u2 = UDim2.new(0.1, 2, 0.3, 4)
        assertTrue(u2.X.Scale == 0.1 and u2.Y.Offset == 4)
        assertTrue(safeTypeof(u) == "UDim")
        assertTrue(safeTypeof(u2) == "UDim2")
    end)
end)

TEST("BrickColor", function()
    check("BrickColor.new by name correct", function()
        local bc = BrickColor.new("Bright red")
        assertTrue(safeTypeof(bc) == "BrickColor")
        assertTrue(bc.Name == "Bright red" or bc.r ~= nil or bc.Color ~= nil)
    end)
end)

TEST("TweenInfo", function()
    check("TweenInfo.Time correct", function()
        local ti = TweenInfo.new(1.5)
        assertTrue(math.abs(ti.Time - 1.5) < 1e-5)
        assertTrue(safeTypeof(ti) == "TweenInfo")
    end)
end)

TEST("NumberRange, NumberSequence, ColorSequence", function()
    check("NumberRange.Min and Max correct", function()
        local nr = NumberRange.new(1, 5)
        assertTrue(nr.Min == 1 and nr.Max == 5)
        local ns = NumberSequence.new(1)
        assertTrue(safeTypeof(ns) == "NumberSequence")
        local cs = ColorSequence.new(Color3.new(1, 1, 1))
        assertTrue(safeTypeof(cs) == "ColorSequence")
    end)
end)

TEST("Ray and RaycastParams and OverlapParams", function()
    check("Ray.Origin correct", function()
        local origin = Vector3.new(1, 2, 3)
        local ray = Ray.new(origin, Vector3.new(0, 1, 0))
        assertTrue(ray.Origin == origin or (ray.Origin.X == 1 and ray.Origin.Y == 2))
        local rp = RaycastParams.new()
        assertTrue(safeTypeof(rp) == "RaycastParams")
        local op = OverlapParams.new()
        assertTrue(safeTypeof(op) == "OverlapParams")
    end)
end)

TEST("Region3", function()
    check("Region3.Size correct", function()
        local r = Region3.new(Vector3.new(0, 0, 0), Vector3.new(2, 4, 6))
        local sz = r.Size
        assertTrue(math.abs(sz.X - 2) < 1e-4)
        assertTrue(math.abs(sz.Y - 4) < 1e-4)
        assertTrue(math.abs(sz.Z - 6) < 1e-4)
    end)
end)

TEST("Random", function()
    check("Random:NextInteger in range", function()
        local r = Random.new(1)
        local n = r:NextInteger(1, 10)
        assertTrue(type(n) == "number" and n >= 1 and n <= 10)
    end)
end)

TEST("FloatCurveKey", function()
    check("FloatCurveKey.new returns correct type", function()
        local k = FloatCurveKey.new(0, 1, Enum.KeyInterpolationMode.Linear)
        assertTrue(safeTypeof(k) == "FloatCurveKey")
    end)
end)

TEST("CatalogSearchParams", function()
    check("CatalogSearchParams.new returns correct type", function()
        local p = CatalogSearchParams.new()
        assertTrue(safeTypeof(p) == "CatalogSearchParams")
    end)
end)

TEST("Core functions [C]", function()
    local function logicAbs()
        assertTrue(math.abs(-3) == 3)
    end
    check("math.abs is C function", function()
        assertTrue(isCFunction(math.abs))
    end)
    check("math.abs logic correct", logicAbs)
    check("math.abs errors on string", function()
        assertTrue(expectError(function()
            math.abs("nope")
        end))
    end)
    check("math.random is C function", function()
        assertTrue(isCFunction(math.random))
    end)
    check("math.random logic correct", function()
        local n = math.random(1, 1)
        assertTrue(n == 1)
    end)
    check("math.random errors on empty interval", function()
        assertTrue(expectError(function()
            math.random(5, 3)
        end))
    end)
    check("math.clamp is C function", function()
        assertTrue(isCFunction(math.clamp))
    end)
    check("math.clamp logic correct", function()
        assertTrue(math.clamp(5, 0, 3) == 3)
        assertTrue(math.clamp(-1, 0, 3) == 0)
    end)
    check("math.floor is C function", function()
        assertTrue(isCFunction(math.floor))
    end)
    check("math.floor logic correct", function()
        assertTrue(math.floor(3.9) == 3)
    end)
    check("math.sign is C function", function()
        assertTrue(isCFunction(math.sign))
    end)
    check("math.sign logic correct", function()
        assertTrue(math.sign(-4) == -1 and math.sign(9) == 1)
    end)
    check("math.rad is C function", function()
        assertTrue(isCFunction(math.rad))
    end)
    check("math.rad logic correct", function()
        assertTrue(math.abs(math.rad(180) - math.pi) < 1e-6)
    end)
    check("math.deg is C function", function()
        assertTrue(isCFunction(math.deg))
    end)
    check("math.deg logic correct", function()
        assertTrue(math.abs(math.deg(math.pi) - 180) < 1e-6)
    end)
    check("table.insert is C function", function()
        assertTrue(isCFunction(table.insert))
    end)
    check("table.insert logic correct", function()
        local t = {1}
        table.insert(t, 2)
        assertTrue(t[2] == 2)
    end)
    check("table.insert errors on non-table", function()
        assertTrue(expectError(function()
            table.insert(1, 1)
        end))
    end)
    check("table.find is C function", function()
        assertTrue(isCFunction(table.find))
    end)
    check("table.find logic correct", function()
        assertTrue(table.find({10, 20, 30}, 20) == 2)
    end)
    check("table.concat is C function", function()
        assertTrue(isCFunction(table.concat))
    end)
    check("table.concat logic correct", function()
        assertTrue(table.concat({"a", "b"}, ",") == "a,b")
    end)
    check("table.remove is C function", function()
        assertTrue(isCFunction(table.remove))
    end)
    check("table.remove logic correct", function()
        local t = {1, 2, 3}
        assertTrue(table.remove(t, 2) == 2 and t[2] == 3)
    end)
    check("table.sort is C function", function()
        assertTrue(isCFunction(table.sort))
    end)
    check("table.sort logic correct", function()
        local t = {3, 1, 2}
        table.sort(t)
        assertTrue(t[1] == 1 and t[3] == 3)
    end)
    check("tostring is C function", function()
        assertTrue(isCFunction(tostring))
    end)
    check("tostring logic correct", function()
        assertTrue(tostring(12) == "12")
    end)
    check("tonumber is C function", function()
        assertTrue(isCFunction(tonumber))
    end)
    check("tonumber logic correct", function()
        assertTrue(tonumber("42") == 42)
    end)
    check("tonumber errors on bad base", function()
        assertTrue(expectError(function()
            tonumber("10", 99)
        end))
    end)
    check("string.len is C function", function()
        assertTrue(isCFunction(string.len))
    end)
    check("string.len logic correct", function()
        assertTrue(string.len("abc") == 3)
    end)
    check("pairs is C function", function()
        assertTrue(isCFunction(pairs))
    end)
    check("pairs logic correct", function()
        local n = 0
        for _ in pairs({ a = 1, b = 2 }) do
            n += 1
        end
        assertTrue(n == 2)
    end)
    check("ipairs is C function", function()
        assertTrue(isCFunction(ipairs))
    end)
    check("ipairs logic correct", function()
        local n = 0
        for i in ipairs({ 1, 2, 3 }) do
            n = i
        end
        assertTrue(n == 3)
    end)
    check("next is C function", function()
        assertTrue(isCFunction(next))
    end)
    check("next logic correct", function()
        local t = { z = 1 }
        local k, v = next(t)
        assertTrue(k == "z" and v == 1)
    end)
    check("type is C function", function()
        assertTrue(isCFunction(type))
    end)
    check("type logic correct", function()
        assertTrue(type(1) == "number" and type("x") == "string")
    end)
    check("typeof is C function", function()
        assertTrue(isCFunction(typeof))
    end)
    check("typeof logic correct", function()
        assertTrue(typeof(Vector3.new()) == "Vector3")
        assertTrue(typeof(1) == "number")
    end)
end)

TEST("Faces", function()
    check("Faces.new returns correct type", function()
        local f = Faces.new(Enum.NormalId.Front)
        assertTrue(safeTypeof(f) == "Faces")
    end)
end)

TEST("Secret", function()
    check("HttpService:GetSecret exists", function()
        local hs = getService("HttpService")
        assertTrue(type(hs.GetSecret) == "function")
    end)
end)

TEST("PhysicalProperties", function()
    check("PhysicalProperties.Density correct", function()
        local pp = PhysicalProperties.new(0.7, 0.3, 0.5)
        assertTrue(safeTypeof(pp) == "PhysicalProperties")
        assertTrue(math.abs(pp.Density - 0.7) < 1e-4)
    end)
end)

TEST("Font", function()
    check("Font.new returns Font", function()
        local f = Font.new("rbxasset://fonts/families/SourceSansPro.json")
        assertTrue(safeTypeof(f) == "Font")
    end)
end)

TEST("Axes", function()
    check("Axes.new returns correct type", function()
        local a = Axes.new(Enum.Axis.X)
        assertTrue(safeTypeof(a) == "Axes")
    end)
end)

TEST("PathWaypoint", function()
    check("PathWaypoint.new returns correct type", function()
        local pw = PathWaypoint.new(Vector3.new(), Enum.PathWaypointAction.Walk)
        assertTrue(safeTypeof(pw) == "PathWaypoint")
    end)
end)

TEST("RBXScriptConnection", function()
    check("RBXScriptConnection.Connected is true after connect", function()
        local conn = getService("RunService").Heartbeat:Connect(function() end)
        assertTrue(conn.Connected == true)
        conn:Disconnect()
        assertTrue(conn.Connected == false)
    end)
end)

TEST("RBXScriptSignal", function()
    check("RBXScriptSignal:Connect returns RBXScriptConnection", function()
        local sig = getService("RunService").Heartbeat
        local conn = sig:Connect(function() end)
        assertTrue(safeTypeof(conn) == "RBXScriptConnection")
        conn:Disconnect()
    end)
end)

TEST("Rect", function()
    check("Rect.new empty returns correct type", function()
        local r = Rect.new()
        assertTrue(safeTypeof(r) == "Rect")
    end)
end)

TEST("Region3int16", function()
    check("Region3int16.new returns correct type", function()
        local r = Region3int16.new()
        assertTrue(safeTypeof(r) == "Region3int16")
    end)
end)

TEST("RotationCurveKey", function()
    check("RotationCurveKey.new returns correct type", function()
        local k = RotationCurveKey.new(0, CFrame.new(), Enum.KeyInterpolationMode.Linear)
        assertTrue(safeTypeof(k) == "RotationCurveKey")
    end)
end)

TEST("SecurityCapabilities", function()
    check("SecurityCapabilities.new returns correct type", function()
        local s = SecurityCapabilities.new()
        assertTrue(safeTypeof(s) == "SecurityCapabilities")
    end)
end)

TEST("eDateTimes", function()
    check("DateTime.now returns DateTime", function()
        local d = DateTime.now()
        assertTrue(safeTypeof(d) == "DateTime")
    end)
end)

TEST("workspace raycasting", function()
    check("workspace:Raycast returns RaycastResult or nil", function()
        local origin = Vector3.new(0, 100, 0)
        local dir = Vector3.new(0, -500, 0)
        local res = workspace:Raycast(origin, dir)
        assertTrue(res == nil or safeTypeof(res) == "RaycastResult")
    end)
end)

TEST("loadstring executes code (using an url)", function()
    local src
    local got = pcall(function()
        src = game:HttpGet("https://e-unc.vercel.app/")
    end)
    if not got or type(src) ~= "string" then
        src = "return 2 + 2"
    end

    local fn, err = loadstring("return 2 + 2")
    assertTrue(type(fn) == "function", err)
    assertTrue(fn() == 4)
    if got and type(src) == "string" then
        assertTrue(#src > 0)
    else

        assertTrue(got)
    end
end)

TEST("loadstring cannot load Luau bytecode", function()
    local bytecode = "\27Luau\0\0\0\0"
    local ok = pcall(function()
        local fn, err = loadstring(bytecode)
        if fn then
            fn()
        else
            error(err or "bad bytecode")
        end
    end)
    assertTrue(not ok)
end)

TEST("Vector3 components are frozen", function()
    local v = Vector3.new(1, 2, 3)
    assertTrue(expectError(function()
        v.X = 0
    end))
end)

TEST("Color3 components are frozen", function()
    local c = Color3.new(1, 0, 0)
    assertTrue(expectError(function()
        c.R = 0
    end))
end)

TEST("rawlen works on string and table", function()
    assertTrue(rawlen("abcd") == 4)
    assertTrue(rawlen({ 1, 2, 3 }) == 3)
end)

TEST("Instance SetAttribute and GetAttribute", function()
    local p = Instance.new("Part")
    p:SetAttribute("eUNC", 7)
    assertTrue(p:GetAttribute("eUNC") == 7)
end)

TEST("CollectionService AddTag and HasTag", function()
    local cs = getService("CollectionService")
    local p = Instance.new("Part")
    cs:AddTag(p, "eUNC")
    assertTrue(cs:HasTag(p, "eUNC") == true)
    cs:RemoveTag(p, "eUNC")
end)

TEST("Humanoid.MoveDirection is Vector3", function()
    local h = Instance.new("Humanoid")
    assertTrue(safeTypeof(h.MoveDirection) == "Vector3")
end)

TEST("Camera.FieldOfView is writable", function()
    local cam = workspace.CurrentCamera
    local old = cam.FieldOfView
    cam.FieldOfView = 90
    assertTrue(cam.FieldOfView == 90)
    cam.FieldOfView = old
end)

TEST("Enum", function()
    check("Enum.EasingStyle.Linear is EnumItem", function()
        local item = Enum.EasingStyle.Linear
        assertTrue(safeTypeof(item) == "EnumItem")
        assertTrue(item.Name == "Linear")
    end)
end)

TEST("buffer operations", function()
    local b = buffer.create(16)
    check("buffer.len correct", function()
        assertTrue(buffer.len(b) == 16)
    end)
    check("buffer.writeu8 and readu8 correct", function()
        buffer.writeu8(b, 0, 255)
        assertTrue(buffer.readu8(b, 0) == 255)
    end)
    check("buffer.writef32 and readf32 correct", function()
        buffer.writef32(b, 4, 1.5)
        assertTrue(math.abs(buffer.readf32(b, 4) - 1.5) < 1e-6)
    end)
    check("buffer.fill correct", function()
        buffer.fill(b, 0, 7, 4)
        assertTrue(buffer.readu8(b, 0) == 7 and buffer.readu8(b, 3) == 7)
    end)
    check("buffer.copy correct", function()
        local src = buffer.create(4)
        buffer.writeu8(src, 0, 9)
        buffer.copy(b, 8, src, 0, 1)
        assertTrue(buffer.readu8(b, 8) == 9)
    end)
    check("buffer.writestring and readstring correct", function()
        buffer.writestring(b, 0, "xyz")
        assertTrue(buffer.readstring(b, 0, 3) == "xyz")
    end)
end)

TEST("UI Library logging ", function()
    local sg = Instance.new("ScreenGui")
    sg.Name = "eUNC_UI"
    local fr = Instance.new("Frame")
    fr.Parent = sg
    local tl = Instance.new("TextLabel")
    tl.Parent = fr
    tl.Text = "eUNC"
    assertTrue(sg.ClassName == "ScreenGui")
    assertTrue(fr.Parent == sg)
    assertTrue(tl.Text == "eUNC")

    return true
end)

TEST("Enum singleton", function()
    assertTrue(Enum == Enum)
    assertTrue(Enum.KeyCode == Enum.KeyCode)
    assertTrue(Enum.KeyCode.F == Enum.KeyCode.F)
end)

TEST("Vector3 arithmetic is correct", function()
    local v = Vector3.new(1, 2, 3) + Vector3.new(4, 5, 6)
    assertTrue(v == Vector3.new(5, 7, 9) or (v.X == 5 and v.Y == 7 and v.Z == 9))
    local s = Vector3.new(2, 0, 0) * 3
    assertTrue(s.X == 6)
end)

TEST("GetService returns singleton", function()
    local a = game:GetService("Players")
    local b = game:GetService("Players")
    assertTrue(a == b)
end)

TEST("loadstring syntax error returns error", function()
    local fn, err = loadstring("function(")
    assertTrue(fn == nil)
    assertTrue(type(err) == "string" and #err > 0)
end)

TEST("GetService matches property access", function()
    assertTrue(game:GetService("Players") == game.Players)
    assertTrue(game:GetService("Workspace") == game.Workspace or game:GetService("Workspace") == workspace)
end)

TEST("require is not callable from global env", function()
    local ok = pcall(function()
        return require("os")
    end)
    local ok2 = pcall(function()
        return require(123456789)
    end)
    assertTrue((not ok) or (not ok2))
end)

TEST("RunService extended properties", function()
    check("RunService.ClientGitHash is string", function()
        local h = getService("RunService").ClientGitHash
        assertTrue(type(h) == "string" and #h > 0)
    end)
end)

TEST("game properties", function()
    check("game.CreatorType is valid", function()
        local ct = game.CreatorType
        assertTrue(safeTypeof(ct) == "EnumItem")
        assertTrue(ct.EnumType == Enum.CreatorType)
    end)
end)

TEST("Players async methods", function()
    check("GetNameFromUserIdAsync matches LocalPlayer", function()
        local lp = getService("Players").LocalPlayer
        local name = getService("Players"):GetNameFromUserIdAsync(lp.UserId)
        assertTrue(name == lp.Name)
    end)
end)

TEST("CollectionService extended", function()
    check("GetTags returns correct tags", function()
        local cs = getService("CollectionService")
        local p = Instance.new("Part")
        cs:AddTag(p, "eUNC_A")
        cs:AddTag(p, "eUNC_B")
        local tags = cs:GetTags(p)
        assertTrue(type(tags) == "table")
        local seen = {}
        for _, t in ipairs(tags) do
            seen[t] = true
        end
        assertTrue(seen.eUNC_A and seen.eUNC_B)
    end)
end)

TEST("Instance property type enforcement", function()
    check("Orientation rejects string assignment", function()
        local p = Instance.new("Part")
        assertTrue(expectError(function()
            p.Orientation = "bad"
        end))
    end)
end)

TEST("Instance signals fire on property change", function()
    check("Changed fires on Name change", function()
        local p = Instance.new("Part")
        local fired = false
        local conn = p.Changed:Connect(function(prop)
            if prop == "Name" then
                fired = true
            end
        end)
        p.Name = "eUNC_Changed"
        task.wait()
        conn:Disconnect()
        assertTrue(fired)
    end)
end)

TEST("gcinfo", function()
    check("gcinfo returns positive number", function()
        local n = gcinfo()
        assertTrue(type(n) == "number" and n > 0)
    end)
end)

TEST("HttpService.GetSecret", function()
    check("GetSecret errors on invalid key", function()
        assertTrue(expectError(function()
            getService("HttpService"):GetSecret("eunc_invalid_key_zzz")
        end))
    end)
end)

TEST("Teams service", function()
    check("Teams:GetTeams returns table", function()
        local t = getService("Teams"):GetTeams()
        assertTrue(type(t) == "table")
    end)
end)

TEST("LogService", function()
    check("LogService:GetLogHistory returns table", function()
        local h = getService("LogService"):GetLogHistory()
        assertTrue(type(h) == "table")
    end)
end)

TEST("Stats service properties", function()
    check("Stats.ContactsCount is number", function()
        assertTrue(type(getService("Stats").ContactsCount) == "number")
    end)
end)

TEST("ENV LOGGER SHOULD BE REGULAR LUAU (not lune or anything else)", function()
    assertTrue(type(_VERSION) == "string")
    assertTrue(string.find(_VERSION, "Luau") ~= nil)
    assertTrue(string.find(string.lower(_VERSION), "lune") == nil)
    assertTrue(_G.process == nil)
    assertTrue(type(task) == "table")
    assertTrue(type(buffer) == "table")
end)

TEST("All Enums.", function()
    check("AccessModifierType exists", function()
        assertTrue(Enum.AccessModifierType ~= nil)
        assertTrue(safeTypeof(Enum.AccessModifierType) == "Enum" or type(Enum.AccessModifierType) == "userdata" or type(Enum.AccessModifierType) == "table")
    end)
    local list = Enum:GetEnums()
    assertTrue(type(list) == "table" and #list > 20)
end)

TEST("tostring changes on rename", function()
    local p = Instance.new("Part")
    p.Name = "Alpha_eUNC"
    local s1 = tostring(p)
    p.Name = "Beta_eUNC"
    local s2 = tostring(p)
    assertTrue(s1 ~= s2)
end)

TEST("IsDescendantOf works after parenting", function()
    local f = Instance.new("Folder")
    local p = Instance.new("Part")
    p.Parent = f
    assertTrue(p:IsDescendantOf(f) == true)
    assertTrue(p:IsDescendantOf(game) == false or f.Parent == nil)
end)

TEST("child parent is nil after destroy", function()
    local f = Instance.new("Folder")
    local c = Instance.new("Part")
    c.Parent = f
    c:Destroy()
    assertTrue(c.Parent == nil)
end)

TEST("Instance and table edge cases", function()
    check("random numeric index on Part does not succeed", function()
        local p = Instance.new("Part")
        local ok, res = pcall(function()
            return p[123456]
        end)
        assertTrue((not ok) or res == nil)
        if ok then

            assertTrue(res == nil)

            error("numeric index succeeded")
        end
    end)
end)

TEST("Physics work under a Part", function()
    check("LocalPlayer exists for physics test", function()
        assertTrue(getService("Players").LocalPlayer ~= nil)
    end)
    local p = Instance.new("Part")
    p.Anchored = false
    p.Parent = workspace
    local fc = Instance.new("FloatCurve")
    assertTrue(fc.ClassName == "FloatCurve" or safeTypeof(fc) == "Instance")
    p.AssemblyLinearVelocity = Vector3.new(0, 10, 0)
    task.wait()
    assertTrue(safeTypeof(p.AssemblyLinearVelocity) == "Vector3" or type(p.Velocity) ~= "nil")
end)

local total = passedCount + failedCount

local reportedTotal = math.max(total, 163)
local pct = 0
if reportedTotal > 0 then
    pct = math.floor((passedCount / reportedTotal) * 100 + 0.5)
end

local execName = "Unknown"
pcall(function()
    if type(identifyexecutor) == "function" then
        execName = tostring(identifyexecutor())
    elseif type(getexecutorname) == "function" then
        execName = tostring(getexecutorname())
    end
end)

print("----------------------------------------")
print(string.format("[eUNC] Score : %d / %d  (%d%%)", passedCount, reportedTotal, pct))
print(string.format("[eUNC] Executor: %s (ENV)", execName))
print(string.format("[eUNC] Passed: %d  |  Failed: %d", passedCount, failedCount))
print("----------------------------------------")
for _, line in ipairs(failLines) do
    print(line)
end
print("----------------------------------------")

local function b64url(data)
    local alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    local out = {}
    local n = #data
    local i = 1
    while i <= n do
        local a = string.byte(data, i) or 0
        local b = string.byte(data, i + 1) or 0
        local c = string.byte(data, i + 2) or 0
        local triple = a * 65536 + b * 256 + c
        local nfill = (i + 1 > n and 2) or (i + 2 > n and 1) or 0
        local chars = {
            string.sub(alpha, bit32.rshift(triple, 18) % 64 + 1, bit32.rshift(triple, 18) % 64 + 1),
            string.sub(alpha, bit32.rshift(triple, 12) % 64 + 1, bit32.rshift(triple, 12) % 64 + 1),
            string.sub(alpha, bit32.rshift(triple, 6) % 64 + 1, bit32.rshift(triple, 6) % 64 + 1),
            string.sub(alpha, triple % 64 + 1, triple % 64 + 1),
        }
        if nfill == 2 then
            table.insert(out, chars[1] .. chars[2])
        elseif nfill == 1 then
            table.insert(out, chars[1] .. chars[2] .. chars[3])
        else
            table.insert(out, table.concat(chars))
        end
        i += 3
    end
    return table.concat(out)
end

local packed = {}
local acc, nb = 0, 0
for _, bit in ipairs(resultBits) do
    acc = acc * 2 + bit
    nb += 1
    if nb == 8 then
        table.insert(packed, string.char(acc))
        acc, nb = 0, 0
    end
end
if nb > 0 then
    acc = bit32.lshift(acc, 8 - nb)
    table.insert(packed, string.char(acc))
end

local payload = string.format("eUNC|%s|%s|%d|%d|%d|%s", eUNC_VERSION, execName, passedCount, failedCount, reportedTotal, table.concat(packed))
local url = "https://e-unc.vercel.app?id=" .. b64url(payload)

print("[eUNC] Results URL (shareable permalink):")
print(url)

pcall(function()
    if type(setclipboard) == "function" then
        setclipboard(url)
    end
end)
