local AntiEnvDetect = require("../src/env/antienv_detect")

local passed, failed = 0, 0
local failures: { string } = {}

local function check(name: string, condition: boolean, detail: string?)
    if condition then
        passed += 1
    else
        failed += 1
        failures[#failures + 1] = name .. (if detail then "  -> " .. detail else "")
    end
end

local function detect(source: string): { [string]: boolean }
    local matches = AntiEnvDetect.analyze(source)
    local ids: { [string]: boolean } = {}
    for _, m in ipairs(matches) do
        ids[m.id] = true
    end
    return ids
end

do
    local ids = detect([[
        if _VERSION ~= "Luau" then
            print("detected")
            return
        end
    ]])
    check("version_check detected", ids["version_check"] == true)
end

do
    local ids = detect([[
        local rs = game:GetService("RunService")
        for i = 1, 100 do
            if rs:IsStudio() then
                print("detected")
                while true do end
            end
            if rs:IsStudio() then
                print("detected")
                while true do end
            end
            if rs:IsStudio() then
                print("detected")
                while true do end
            end
        end
    ]])
    check("isstudio_loop detected (>=3 calls)", ids["isstudio_loop"] == true)
end

do
    local ids = detect([[
        if game:GetService("RunService"):IsStudio() then
            error("no studio")
        end
    ]])
    check("isstudio_check detected (1 call)", ids["isstudio_check"] == true)
    check("isstudio_loop NOT triggered for single call", ids["isstudio_loop"] ~= true)
end

do
    local ids = detect([[
        local success, res = pcall(function() return game:GetService("CorePackages") end)
        if not success then
            print("detected")
            return
        end
    ]])
    check("corepackages_check detected", ids["corepackages_check"] == true)
end

do
    local ids = detect([[
        local Players = game:GetService("Players")
        local function validate()
            for _, player in ipairs(Players:GetPlayers()) do
                if not player:IsA("Player") then
                    return false
                end
            end
            return true
        end
    ]])
    check("player_validate detected", ids["player_validate"] == true)
end

do
    local ids = detect([[
        local vcs = game:GetService("VoiceChatService")
        if type(vcs.joinVoice) ~= "function" then error("detected") end
        if type(vcs.rejoinVoice) ~= "function" then error("detected") end
        if type(vcs.leaveVoice) ~= "function" then error("detected") end
    ]])
    check("vc_methods detected", ids["vc_methods"] == true)
end

do
    local ids = detect([[
        local ss = game:GetService("SoundService")
        if type(ss.GetAudioInstances) ~= "function" then error("detected") end
        if type(ss.GetInputDevices) ~= "function" then error("detected") end
        if type(ss.GetOutputDevices) ~= "function" then error("detected") end
    ]])
    check("ss_methods detected", ids["ss_methods"] == true)
end

do
    local ids = detect([[
        local asset = game:GetService("AssetService")
        local mesh = asset:CreateEditableMesh()
        local v = mesh:AddVertex(Vector3.new(1, 2, 3))
        local pos = mesh:GetPosition(v)
        mesh:Destroy()
        if pos.X ~= 1 then error("detected") end
    ]])
    check("mesh_roundtrip detected", ids["mesh_roundtrip"] == true)
end

do
    local ids = detect([[
        local success, lune = pcall(function() return require("@lune/fs") end)
        if success then
            print("detected - running on Lune")
            return
        end
    ]])
    check("lune_detect detected", ids["lune_detect"] == true)
end

do
    local ids = detect([[
        local a = SharedTable.new()
        local b = SharedTable.cloneAndFreeze(a, true)
        if not SharedTable.isFrozen(b) then error("detected") end
    ]])
    check("sharedtable_check detected", ids["sharedtable_check"] == true)
end

do
    local ids = detect([[
        local name = identifyexecutor()
        if name == "Synapse" then

        end
    ]])
    check("executor_check detected", ids["executor_check"] == true)
end

do
    local ids = detect([[
        local hwid = gethwid()
        if hwid ~= expected then error("detected") end
    ]])
    check("hwid_check detected", ids["hwid_check"] == true)
end

do
    local ids = detect([[
        local mt = getrawmetatable(game)
        if mt == nil then error("detected") end
    ]])
    check("metatable_probe detected", ids["metatable_probe"] == true)
end

do
    local ids = detect([[
        local old = hookfunction(print, function() end)
        if old == nil then error("detected") end
    ]])
    check("hook_check detected", ids["hook_check"] == true)
end

do
    local ids = detect([[
        if not islclosure(someFunc) then error("detected") end
    ]])
    check("closure_type_check detected", ids["closure_type_check"] == true)
end

do
    local ids = detect([[
        local conns = getconnections(game:GetService("Players").PlayerAdded)
        if #conns > 0 then error("detected") end
    ]])
    check("signal_probe detected", ids["signal_probe"] == true)
end

do
    local ids = detect([[
        print("detected by 6Vms")
        while true do end
    ]])
    check("detection_msg detected", ids["detection_msg"] == true)
end

do
    local ids = detect([[
        local identity = getthreadidentity()
        if identity < 8 then error("detected") end
    ]])
    check("identity_check detected", ids["identity_check"] == true)
end

do
    local ids = detect([[
        local Players = game:GetService("Players")
        local player = Players.LocalPlayer
        print("Hello " .. player.Name)
    ]])
    local count = 0
    for _ in pairs(ids) do count += 1 end
    check("clean script has no detections", count == 0)
end

do
    local ids = detect([[
        if _VERSION ~= "Luau" then error("detected") end
        local rs = game:GetService("RunService")
        for i = 1, 50 do
            if rs:IsStudio() then error("detected") end
            if rs:IsStudio() then error("detected") end
            if rs:IsStudio() then error("detected") end
        end
        local name = identifyexecutor()
        if name ~= "KRNL" then error("detected") end
    ]])
    local count = 0
    for _ in pairs(ids) do count += 1 end
    check("multiple patterns detected", count >= 3, "found " .. tostring(count))
    check("version_check in multi-pattern", ids["version_check"] == true)
    check("isstudio_loop in multi-pattern", ids["isstudio_loop"] == true)
    check("executor_check in multi-pattern", ids["executor_check"] == true)
end

do
    local matches = AntiEnvDetect.analyze([[
        if _VERSION ~= "Luau" then error("detected") end
        local rs = game:GetService("RunService")
        for i = 1, 100 do
            if rs:IsStudio() then error("detected") end
        end
        local vcs = game:GetService("VoiceChatService")
        if type(vcs.joinVoice) ~= "function" then error("detected") end
    ]])
    check("matches sorted by severity", #matches >= 2)
    if #matches >= 2 then
        local sevOrder = { critical = 3, warn = 2, info = 1 }
        local first = sevOrder[matches[1].severity] or 0
        local second = sevOrder[matches[2].severity] or 0
        check("first match is more severe than or equal to second", first >= second,
            first .. " >= " .. second)
    end
end

print(string.format("\nantienv_detect: %d passed, %d failed", passed, failed))
if failed > 0 then
    for _, line in ipairs(failures) do
        print("  FAIL  " .. line)
    end
    error("test failures")
end
