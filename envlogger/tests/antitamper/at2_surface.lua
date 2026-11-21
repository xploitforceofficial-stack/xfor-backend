local a = {}
local function r(n, f) a[#a+1] = {n, f} end

r("1", function() return typeof(workspace.CurrentCamera.FieldOfView) == "number" end)
r("2", function() return typeof(workspace.CurrentCamera.Focus) == "CFrame" end)
r("3", function() return true end)
r("4", function() return typeof(game:GetService("Lighting").Brightness) == "number" end)
r("5", function() return typeof(game:GetService("Lighting").Ambient) == "Color3" end)
r("6", function() return typeof(game:GetService("Lighting").OutdoorAmbient) == "Color3" end)
r("7", function() return typeof(game:GetService("Lighting").Technology) == "EnumItem" end)
r("8", function() local t = workspace:FindFirstChildOfClass("Terrain") return t ~= nil end)
r("9", function()
    local t = workspace:FindFirstChildOfClass("Terrain")
    if not t then return true end
    local ok = pcall(function() return t:ReadVoxels(Region3.new(Vector3.new(0,0,0), Vector3.new(4,4,4)):ExpandToGrid(4), 4) end)
    return ok
end)
r("10", function() return typeof(game.CreatorId) == "number" end)
r("11", function() return typeof(game.CreatorType) == "EnumItem" end)
r("12", function() return typeof(game.PlaceVersion) == "number" and game.PlaceVersion > 0 end)
r("13", function() return typeof(game:IsLoaded()) == "boolean" end)
r("14", function() return typeof(workspace.Gravity) == "number" and workspace.Gravity > 0 end)
r("15", function() return typeof(workspace.FallenPartsDestroyHeight) == "number" end)
r("16", function() return typeof(workspace.DistributedGameTime) == "number" end)
r("17", function()
    local ok = pcall(function()
        local p = Instance.new("Part")
        p.Parent = workspace
        local t = game:GetService("TweenService"):Create(p, TweenInfo.new(0.3), {Transparency = 1})
        t:Play()
        task.wait(0.4)
        p:Destroy()
    end)
    return ok
end)
r("18", function()
    local ok = pcall(function()
        local path = game:GetService("PathfindingService"):CreatePath()
        path:ComputeAsync(Vector3.new(0,0,0), Vector3.new(10,0,10))
    end)
    return ok
end)
r("19", function()
    local ok, res = pcall(function()
        local p = Instance.new("Part")
        p.Parent = workspace
        game:GetService("CollectionService"):AddTag(p, "dtc_tag")
        local h = game:GetService("CollectionService"):HasTag(p, "dtc_tag")
        p:Destroy()
        return h
    end)
    return ok and res == true
end)
r("20", function()
    local ok = pcall(function() game:GetService("ContentProvider"):PreloadAsync({"rbxassetid://1"}) end)
    return ok
end)
r("22", function()
    local ok, size = pcall(function()
        return game:GetService("TextService"):GetTextSize("test", 14, Enum.Font.SourceSans, Vector2.new(200,50))
    end)
    return ok and typeof(size) == "Vector2"
end)
r("23", function() return game:GetService("ProximityPromptService") ~= nil end)
r("25", function()
    local ok = pcall(function()
        local p = Instance.new("Part")
        game:GetService("Debris"):AddItem(p, 0.1)
    end)
    return ok
end)
r("26", function()
    local ok, hist = pcall(function() return game:GetService("LogService"):GetLogHistory() end)
    return ok and typeof(hist) == "table"
end)
r("27", function()
    local g = game:GetService("HttpService"):GenerateGUID(false)
    return typeof(g) == "string" and #g == 36
end)
r("28", function()
    local h = game:GetService("HttpService")
    local ok, enc = pcall(function() return h:JSONEncode({a=1,b="x"}) end)
    if not ok then return false end
    local ok2, dec = pcall(function() return h:JSONDecode(enc) end)
    return ok2 and dec.a == 1 and dec.b == "x"
end)
r("29", function() return typeof(game:GetService("HttpService").HttpEnabled) == "boolean" end)
r("30", function()
    local ok, inst = pcall(function() return Instance.new("Part") end)
    return ok and typeof(inst) == "Instance"
end)
r("31", function()
    local p = Instance.new("Part")
    p.Name = "dtc_p"
    p.Parent = workspace
    local full = p:GetFullName()
    p:Destroy()
    return typeof(full) == "string" and string.find(full, "dtc_p") ~= nil
end)
r("32", function()
    local p = Instance.new("Part")
    return p:IsA("BasePart") and p:IsA("PVInstance")
end)
r("33", function()
    local m = Instance.new("Model")
    local p1 = Instance.new("Part") p1.Parent = m
    local p2 = Instance.new("Part") p2.Parent = m
    return #m:GetChildren() == 2
end)
r("34", function()
    local p = Instance.new("Part")
    p.Name = "dtc_orig"
    local c = p:Clone()
    return c.Name == "dtc_orig" and c ~= p
end)
r("35", function()
    local p = Instance.new("Part")
    p.Parent = workspace
    local fired = false
    local con = p.Changed:Connect(function() fired = true end)
    p.Transparency = 0.5
    task.wait(0.1)
    con:Disconnect()
    p:Destroy()
    return fired
end)
r("36", function()
    local p = Instance.new("Part")
    p.Parent = workspace
    local fired = false
    local con = p:GetPropertyChangedSignal("Transparency"):Connect(function() fired = true end)
    p.Transparency = 0.7
    task.wait(0.1)
    con:Disconnect()
    p:Destroy()
    return fired
end)
r("37", function()
    local ok = pcall(function()
        local p1 = Instance.new("Part") p1.Parent = workspace
        local p2 = Instance.new("Part") p2.Parent = workspace
        local w = Instance.new("WeldConstraint")
        w.Part0 = p1
        w.Part1 = p2
        w.Parent = p1
        p1:Destroy() p2:Destroy()
    end)
    return ok
end)
r("38", function()
    local ok, res = pcall(function()
        local m = Instance.new("Model")
        local h = Instance.new("Humanoid")
        h.MaxHealth = 100
        h.Health = 100
        h.Parent = m
        h:TakeDamage(20)
        local r = h.Health == 80
        m:Destroy()
        return r
    end)
    return ok and res
end)
r("40", function()
    local ok = pcall(function()
        local bv = Instance.new("BodyVelocity")
        bv.Velocity = Vector3.new(0,10,0)
        local p = Instance.new("Part")
        p.Anchored = false
        p.Parent = workspace
        bv.Parent = p
        task.wait(0.2)
        p:Destroy()
    end)
    return ok
end)
r("41", function()
    local ok = pcall(function()
        local p = Instance.new("Part")
        p.Parent = workspace
        local ff = Instance.new("ForceField")
        ff.Parent = p
        p:Destroy()
    end)
    return ok
end)
r("42", function() return pcall(function() Instance.new("Explosion") end) end)
r("43", function()
    local part = Instance.new("Part")
    part.Size = Vector3.new(100,100,100)
    part.Anchored = true
    part.Parent = workspace
    local found = workspace:GetPartBoundsInBox(part.CFrame, part.Size)
    part:Destroy()
    return typeof(found) == "table"
end)
r("44", function()
    return pcall(function()
        local sg = Instance.new("SoundGroup")
        sg.Volume = 0.5
        local s = Instance.new("Sound")
        s.SoundGroup = sg
    end)
end)
r("45", function()
    return pcall(function()
        local p = Instance.new("Attachment")
        p.Position = Vector3.new(1,1,1)
        local w = p.WorldPosition
    end)
end)
r("46", function()
    return pcall(function()
        local pe = Instance.new("ParticleEmitter")
        pe.Rate = 10
        local p = Instance.new("Part")
        pe.Parent = p
    end)
end)
r("47", function()
    return pcall(function()
        local a1 = Instance.new("Attachment")
        local a2 = Instance.new("Attachment")
        local tr = Instance.new("Trail")
        tr.Attachment0 = a1
        tr.Attachment1 = a2
    end)
end)
r("48", function()
    return pcall(function()
        local a1 = Instance.new("Attachment")
        local a2 = Instance.new("Attachment")
        local b = Instance.new("Beam")
        b.Attachment0 = a1
        b.Attachment1 = a2
    end)
end)
r("49", function()
    return pcall(function()
        game:GetService("ContextActionService"):BindAction("dtc", function() end, false, Enum.KeyCode.Q)
        game:GetService("ContextActionService"):UnbindAction("dtc")
    end)
end)
r("50", function()
    local ok, inset = pcall(function() return game:GetService("GuiService"):GetGuiInset() end)
    return ok and typeof(inset) == "Vector2"
end)
r("51", function()
    return pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", {Title="t", Text="t"}) end)
end)
r("52", function() return game:GetService("TextChatService") ~= nil end)
r("53", function()
    local rs = game:GetService("RunService")
    return rs:IsClient() == true and rs:IsServer() == false
end)
r("54", function() return typeof(game:GetService("RunService"):IsStudio()) == "boolean" end)
r("55", function()
    local ok, con = pcall(function() return game:GetService("RunService").RenderStepped:Connect(function() end) end)
    if ok and con then con:Disconnect() end
    return ok
end)
r("56", function()
    local rs = game:GetService("RunService")
    local fired = false
    local con = rs.Stepped:Connect(function() fired = true end)
    task.wait(0.2)
    con:Disconnect()
    return fired
end)
r("58", function() return typeof(game:GetService("Players").LocalPlayer.MembershipType) == "EnumItem" end)
r("59", function()
    local p = game:GetService("Players").LocalPlayer
    return typeof(p.AccountAge) == "number" and p.AccountAge >= 0
end)
r("60", function()
    local p = game:GetService("Players").LocalPlayer
    return p.Team == nil or typeof(p.Team) == "Instance"
end)
r("61", function()
    local pl = game:GetService("Players"):GetPlayers()
    return typeof(pl) == "table" and #pl >= 1
end)
r("62", function() return typeof(game:GetService("Players").MaxPlayers) == "number" end)
r("63", function() return true end)
r("64", function() return typeof(game:GetService("Players").LocalPlayer.CharacterAppearanceId) == "number" end)
r("65", function()
    local p = game:GetService("Players").LocalPlayer
    return typeof(p.DisplayName) == "string" and #p.DisplayName > 0
end)
r("66", function()
    local p = game:GetService("Players").LocalPlayer
    return typeof(p.Name) == "string" and #p.Name > 0
end)
r("67", function()
    return pcall(function()
        return game:GetService("Players"):GetUserThumbnailAsync(1, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
    end)
end)
r("68", function()
    local m = Instance.new("Model")
    local h = Instance.new("Humanoid")
    h.Parent = m
    local hrp = Instance.new("Part")
    hrp.Name = "HumanoidRootPart"
    hrp.Parent = m
    local ok = pcall(function() h:MoveTo(Vector3.new(5,0,5)) end)
    m:Destroy()
    return ok
end)
r("69", function()
    return pcall(function()
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://1"
    end)
end)
r("71", function()
    return pcall(function()
        return game:GetService("BadgeService"):UserHasBadgeAsync(game.Players.LocalPlayer.UserId, 1)
    end)
end)
r("72", function() return game:GetService("SocialService") ~= nil end)
r("73", function() return pcall(function() game:GetService("GamePassService") end) end)
r("74", function()
    return pcall(function()
        return game:GetService("LocalizationService"):GetCountryRegionForPlayerAsync(game.Players.LocalPlayer)
    end)
end)
r("75", function()
    return game:GetService("VRService") ~= nil and typeof(game:GetService("VRService").VREnabled) == "boolean"
end)
r("76", function() return game:GetService("HapticService") ~= nil end)
r("77", function() return pcall(function() game:GetService("TeleportService"):GetLocalPlayerTeleportData() end) end)
r("78", function() return typeof(game.JobId) == "string" end)
r("79", function() return typeof(game.GameId) == "number" and game.GameId > 0 end)
r("80", function() return game.Players.LocalPlayer:FindFirstChild("PlayerGui") ~= nil end)
r("81", function() return game.Players.LocalPlayer:FindFirstChild("Backpack") ~= nil end)
r("82", function() return game.Players.LocalPlayer:FindFirstChild("PlayerScripts") ~= nil end)
r("83", function() return game:GetService("StarterPack") ~= nil end)
r("84", function() return game:GetService("StarterGui") ~= nil end)
r("85", function()
    return pcall(function()
        return game:GetService("Chat"):FilterStringForBroadcast("test", game.Players.LocalPlayer)
    end)
end)
r("86", function() return game:GetService("Workspace").Name == "Workspace" end)
r("87", function() return typeof(game:GetService("ReplicatedStorage")) == "Instance" end)
r("88", function() return typeof(game:GetService("ReplicatedFirst")) == "Instance" end)
r("89", function() return pcall(function() return game:GetService("ServerStorage"):GetChildren() end) end)
r("90", function() return pcall(function() game:GetService("ServerScriptService") end) end)
r("91", function() return typeof(game:GetService("SoundService")) == "Instance" end)
r("92", function() return pcall(function() return TweenInfo.new(1) end) end)
r("93", function()
    local ok, region = pcall(function() return Region3.new(Vector3.new(0,0,0), Vector3.new(10,10,10)) end)
    return ok and typeof(region) == "Region3"
end)
r("94", function()
    local ok, cf = pcall(function() return CFrame.new(0,0,0) * CFrame.Angles(0,math.rad(90),0) end)
    return ok and typeof(cf) == "CFrame"
end)
r("95", function()
    local v = Vector3.new(1,2,3)
    return typeof(v.Magnitude) == "number" and math.abs(v.Magnitude - math.sqrt(14)) < 0.01
end)
r("96", function()
    local c = Color3.fromRGB(255,0,0)
    return c.R == 1 and c.G == 0 and c.B == 0
end)
r("97", function()
    local ud = UDim2.new(0.5,10,0.5,10)
    return ud.X.Scale == 0.5 and ud.X.Offset == 10
end)
r("98", function()
    local ok, res = pcall(function() return game:GetService("RunService").Heartbeat:Wait() end)
    return ok and typeof(res) == "number"
end)
r("99", function()
    local ok, seq = pcall(function() return NumberSequence.new(0,1) end)
    return ok and typeof(seq) == "NumberSequence"
end)
r("100", function()
    local ok, seq = pcall(function() return ColorSequence.new(Color3.new(1,0,0), Color3.new(0,1,0)) end)
    return ok and typeof(seq) == "ColorSequence"
end)

local cl = {"Part","WedgePart","MeshPart","UnionOperation","Model","Folder","Script","LocalScript","ModuleScript","Frame","TextLabel","TextButton","TextBox","ImageLabel","ImageButton","ScrollingFrame","ViewportFrame","BillboardGui","SurfaceGui","ScreenGui","Sound","SoundGroup","ParticleEmitter","Trail","Beam","Smoke","Fire","Sparkles","PointLight","SpotLight","SurfaceLight","Weld","WeldConstraint","Motor6D","HingeConstraint","RodConstraint","RopeConstraint","SpringConstraint","BallSocketConstraint","PrismaticConstraint"}
for i, cn in ipairs(cl) do
    r("G1_"..i, function()
        local ok, inst = pcall(Instance.new, cn)
        return ok and typeof(inst) == "Instance"
    end)
end

local en = {"KeyCode","UserInputType","Material","PartType","HumanoidStateType","ThumbnailType","ThumbnailSize","Font","TextXAlignment","TextYAlignment","EasingStyle","EasingDirection","CameraType","CameraMode","DevCameraOcclusionMode","AnimationPriority","BodyPartR15","SurfaceType","FrameStyle","SizeConstraint","AutomaticSize","ButtonStyle","VerticalAlignment","HorizontalAlignment","NormalId","Axis","SortOrder","ScrollingDirection","DevTouchMovementMode"}
for i, en_name in ipairs(en) do
    r("G2_"..i, function()
        local ok, items = pcall(function() return Enum[en_name]:GetEnumItems() end)
        return ok and typeof(items) == "table" and #items > 0
    end)
end

local sv = {"Workspace","Players","Lighting","ReplicatedStorage","ReplicatedFirst","ServerScriptService","ServerStorage","StarterGui","StarterPack","StarterPlayer","Teams","SoundService","Chat","LocalizationService","TextService","TweenService","RunService","UserInputService","ContextActionService","GuiService","HttpService","MarketplaceService","BadgeService","GamePassService","InsertService","PathfindingService","CollectionService","Debris","PhysicsService","ProximityPromptService"}
for i, sv_name in ipairs(sv) do
    r("G3_"..i, function()
        local ok, svc = pcall(function() return game:GetService(sv_name) end)
        return ok and typeof(svc) == "Instance"
    end)
end

local fn = {
    {"tostring", tostring}, {"tonumber", tonumber}, {"type", type}, {"typeof", typeof},
    {"pairs", pairs}, {"ipairs", ipairs}, {"next", next}, {"select", select},
    {"rawget", rawget}, {"rawset", rawset}, {"rawequal", rawequal}, {"rawlen", rawlen},
    {"setmetatable", setmetatable}, {"getmetatable", getmetatable}, {"pcall", pcall},
    {"xpcall", xpcall}, {"error", error}, {"assert", assert}, {"unpack", table.unpack},
    {"require", require}, {"delay", task.delay}, {"wait", task.wait}, {"spawn", task.spawn},
    {"tick", tick}, {"time", time}, {"warn", warn}, {"print", print},
    {"collectgarbage", collectgarbage}, {"loadstring", loadstring}, {"newproxy", newproxy}
}
for i, pr in ipairs(fn) do
    r("G4_"..i, function() return type(pr[2]) == "function" end)
end

local dt = {
    {function() return Vector2.new(1,2) end, "Vector2"},
    {function() return Vector3.new(1,2,3) end, "Vector3"},
    {function() return Vector2int16.new(1,2) end, "Vector2int16"},
    {function() return Vector3int16.new(1,2,3) end, "Vector3int16"},
    {function() return CFrame.new(0,0,0) end, "CFrame"},
    {function() return Color3.new(1,1,1) end, "Color3"},
    {function() return UDim.new(0.5,10) end, "UDim"},
    {function() return UDim2.new(0.5,10,0.5,10) end, "UDim2"},
    {function() return Rect.new(0,0,10,10) end, "Rect"},
    {function() return Ray.new(Vector3.new(0,0,0), Vector3.new(0,-1,0)) end, "Ray"},
    {function() return Region3.new(Vector3.new(0,0,0), Vector3.new(1,1,1)) end, "Region3"},
    {function() return Region3int16.new(Vector3int16.new(0,0,0), Vector3int16.new(1,1,1)) end, "Region3int16"},
    {function() return NumberRange.new(0,10) end, "NumberRange"},
    {function() return NumberSequence.new(0,1) end, "NumberSequence"},
    {function() return ColorSequence.new(Color3.new(1,0,0)) end, "ColorSequence"},
    {function() return PhysicalProperties.new(1,1,1) end, "PhysicalProperties"},
    {function() return Random.new() end, "Random"},
    {function() return BrickColor.new("Bright red") end, "BrickColor"},
    {function() return Faces.new(Enum.NormalId.Top) end, "Faces"},
    {function() return Axes.new(Enum.Axis.X) end, "Axes"}
}
for i, it in ipairs(dt) do
    r("G5_"..i, function()
        local ok, val = pcall(it[1])
        return ok and typeof(val) == it[2]
    end)
end

local pt = {
    {function() return workspace.CurrentCamera.CFrame end, "CFrame"},
    {function() return workspace.CurrentCamera.CameraType end, "EnumItem"},
    {function() return game:GetService("UserInputService").TouchEnabled end, "boolean"},
    {function() return game:GetService("UserInputService").KeyboardEnabled end, "boolean"},
    {function() return game:GetService("UserInputService").MouseEnabled end, "boolean"},
    {function() return game:GetService("UserInputService").GamepadEnabled end, "boolean"},
    {function() return game:GetService("UserInputService").VREnabled end, "boolean"},
    {function() return game:GetService("UserInputService").AccelerometerEnabled end, "boolean"},
    {function() return game:GetService("UserInputService").GyroscopeEnabled end, "boolean"},
    {function() return game:GetService("UserInputService").OnScreenKeyboardVisible end, "boolean"},
    {function() return game:GetService("Lighting").FogColor end, "Color3"},
    {function() return game:GetService("Lighting").FogStart end, "number"},
    {function() return game:GetService("Lighting").FogEnd end, "number"},
    {function() return game:GetService("Lighting").ColorShift_Top end, "Color3"},
    {function() return game:GetService("Lighting").ColorShift_Bottom end, "Color3"},
    {function() return game:GetService("Lighting").EnvironmentDiffuseScale end, "number"},
    {function() return game:GetService("Lighting").EnvironmentSpecularScale end, "number"},
    {function() return game:GetService("Lighting").GlobalShadows end, "boolean"},
    {function() return game:GetService("Lighting").ShadowSoftness end, "number"},
    {function() return game:GetService("Lighting").GeographicLatitude end, "number"},
    {function() return game:GetService("SoundService").AmbientReverb end, "EnumItem"},
    {function() return game:GetService("SoundService").DistanceFactor end, "number"},
    {function() return game:GetService("SoundService").DopplerScale end, "number"},
    {function() return game:GetService("SoundService").RolloffScale end, "number"},
    {function() return game:GetService("Players").LocalPlayer.CameraMinZoomDistance end, "number"},
    {function() return game:GetService("Players").LocalPlayer.CameraMaxZoomDistance end, "number"},
    {function() return game:GetService("Players").LocalPlayer.DevCameraOcclusionMode end, "EnumItem"},
    {function() return game:GetService("Players").LocalPlayer.DevComputerCameraMode end, "EnumItem"},
    {function() return game:GetService("Players").LocalPlayer.DevTouchMovementMode end, "EnumItem"},
    {function() return game:GetService("Players").LocalPlayer.Neutral end, "boolean"}
}
for i, it in ipairs(pt) do
    r("G6_"..i, function()
        local ok, val = pcall(it[1])
        return ok and typeof(val) == it[2]
    end)
end

r("G7_1", function() return string.format("%d",5) == "5" end)
r("G7_2", function() return string.rep("a",3) == "aaa" end)
r("G7_3", function() return string.byte("A") == 65 end)
r("G7_4", function() return string.char(65) == "A" end)
r("G7_5", function() return string.sub("hello",2,3) == "el" end)
r("G7_6", function() local s = string.gsub("hello","l","L") return s == "heLLo" end)
r("G7_7", function() return table.concat({1,2,3},",") == "1,2,3" end)
r("G7_8", function() local t = {3,1,2} table.sort(t) return t[1] == 1 end)
r("G7_9", function() local t = {1,2,3} table.insert(t,4) table.remove(t,1) return t[1] == 2 and #t == 3 end)
r("G7_10", function()
    local ok, c = pcall(function() return table.clone({1,2,3}) end)
    return ok and typeof(c) == "table"
end)
r("G7_11", function() return math.clamp(5,0,10) == 5 and math.clamp(-5,0,10) == 0 end)
r("G7_12", function() return math.floor(2.5) == 2 end)
r("G7_13", function() return 1/0 == math.huge end)
r("G7_14", function()
    local ok, v = pcall(function() return bit32.band(6,3) end)
    return ok and v == 2
end)
r("G7_15", function() return typeof(os.time()) == "number" end)
r("G7_16", function() return typeof(os.date()) == "string" end)
r("G7_17", function() return coroutine.status(coroutine.create(function() end)) == "suspended" end)
r("G7_18", function()
    local w = coroutine.wrap(function() coroutine.yield(1) end)
    return w() == 1
end)
r("G7_19", function() return select("#",1,2,3) == 3 end)
r("G7_20", function()
    local ok, c = pcall(function() return utf8.char(65) end)
    return ok and c == "A"
end)

local s = {}
for i = 1, #a do
    local n, f = a[i][1], a[i][2]
    local ok, res = pcall(f)
    if not ok or not res then
        s[#s + 1] = n
    end
end

if #s == 0 then
    print("pass")
else
    print(table.concat(s, ", "))
end
