local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

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

local function outputsOf(source: string, timeout: number?): ({ string }, any)
    local result = Sandbox.run(source, { timeout = timeout or 30, maxExplored = 0 })
    local lines: { string } = {}
    for _, entry in ipairs(result.outputs or {}) do
        lines[#lines + 1] = string.gsub(tostring(entry.text), "\t", " ")
    end
    return lines, result
end

do
    local lines, result = outputsOf([[
        if _VERSION ~= "Luau" then
            print("FAIL:1")
            return
        end
        print("pass")
    ]])
    check("_VERSION == Luau", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        if type(_G) ~= "table" then
            print("FAIL:2")
            return
        end
        if not string.find(tostring(_G), "table: ") then
            print("FAIL:2b")
            return
        end
        print("pass")
    ]])
    check("_G is table with correct tostring", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local rs = game:GetService("RunService")
        if rs:IsStudio() then
            print("FAIL:3")
            return
        end
        print("pass")
    ]])
    check("IsStudio() returns false", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local success, res = pcall(function() return game:GetService("CorePackages") end)

        print("pass")
    ]])
    check("CorePackages pcall succeeds", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local Players = game:GetService("Players")
        local list = Players:GetPlayers()
        if type(list) ~= "table" then
            print("FAIL:5a")
            return
        end
        if #list == 0 then
            print("FAIL:5b - empty")
            return
        end
        for _, player in ipairs(list) do
            if not player:IsA("Player") then
                print("FAIL:5c - not Player")
                return
            end
        end
        print("pass")
    ]])
    check("Players:GetPlayers() validation", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local vcs = game:GetService("VoiceChatService")
        if type(vcs.joinVoice) ~= "function" then
            print("FAIL:6a")
            return
        end
        if type(vcs.rejoinVoice) ~= "function" then
            print("FAIL:6b")
            return
        end
        if type(vcs.leaveVoice) ~= "function" then
            print("FAIL:6c")
            return
        end
        print("pass")
    ]])
    check("VoiceChatService method types", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local ss = game:GetService("SoundService")
        if type(ss.GetAudioInstances) ~= "function" then
            print("FAIL:7a")
            return
        end
        if type(ss.GetInputDevices) ~= "function" then
            print("FAIL:7b")
            return
        end
        if type(ss.GetOutputDevices) ~= "function" then
            print("FAIL:7c")
            return
        end
        print("pass")
    ]])
    check("SoundService method types", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local asset = game:GetService("AssetService")
        if not asset or not asset.CreateEditableMesh then
            print("FAIL:8a - no CreateEditableMesh")
            return
        end
        local mesh = asset:CreateEditableMesh()
        if not mesh then
            print("FAIL:8b - nil mesh")
            return
        end
        local v = mesh:AddVertex(Vector3.new(5, 10, 15))
        local pos = mesh:GetPosition(v)
        mesh:Destroy()
        if pos and math.abs(pos.X - 5) < 1e-4 and math.abs(pos.Y - 10) < 1e-4 and math.abs(pos.Z - 15) < 1e-4 then
            print("pass")
        else
            print("FAIL:8c - position mismatch")
        end
    ]])
    check("AssetService mesh round-trip", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local failures = {}
        if typeof(workspace) ~= "Instance" then failures[#failures+1] = "workspace" end
        if typeof(game:GetService("Players")) ~= "Instance" then failures[#failures+1] = "Players" end
        if typeof(Vector3.new(1,2,3)) ~= "Vector3" then failures[#failures+1] = "Vector3" end
        if typeof(Vector2.new(1,2)) ~= "Vector2" then failures[#failures+1] = "Vector2" end
        if typeof(CFrame.new()) ~= "CFrame" then failures[#failures+1] = "CFrame" end
        if typeof(Color3.new(1,1,1)) ~= "Color3" then failures[#failures+1] = "Color3" end
        if typeof(1) ~= "number" then failures[#failures+1] = "number" end
        if typeof("x") ~= "string" then failures[#failures+1] = "string" end
        if typeof(true) ~= "boolean" then failures[#failures+1] = "boolean" end
        if typeof({}) ~= "table" then failures[#failures+1] = "table" end
        if typeof(nil) ~= "nil" then failures[#failures+1] = "nil" end
        if typeof(function() end) ~= "function" then failures[#failures+1] = "function" end
        if #failures > 0 then
            print("FAIL:9 - " .. table.concat(failures, ", "))
        else
            print("pass")
        end
    ]])
    check("typeof() correctness", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[

        local ok1 = pcall(function() Instance.new("Part") end)
        local ok2 = pcall(function() Instance.new("ScreenGui") end)
        local ok3 = pcall(function() Instance.new("Folder") end)

        local ok4, err4 = pcall(function() Instance.new("NonExistentClass123") end)
        if not ok1 or not ok2 or not ok3 then
            print("FAIL:10a - valid class rejected")
        elseif ok4 then
            print("FAIL:10b - invalid class accepted")
        elseif not string.find(tostring(err4), "Unable to create class") then
            print("FAIL:10c - wrong error message: " .. tostring(err4))
        else
            print("pass")
        end
    ]])
    check("Instance.new class validation", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local p = Instance.new("Part")
        if not p:IsA("BasePart") then
            print("FAIL:11a")
            return
        end
        if not p:IsA("Part") then
            print("FAIL:11b")
            return
        end
        if p:IsA("ScreenGui") then
            print("FAIL:11c")
            return
        end
        print("pass")
    ]])
    check("Instance:IsA() hierarchy", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local Lighting = game:GetService("Lighting")
        if typeof(Lighting.Brightness) ~= "number" then
            print("FAIL:12a")
            return
        end
        if typeof(Lighting.Ambient) ~= "Color3" then
            print("FAIL:12b")
            return
        end
        if typeof(Lighting.Technology) ~= "EnumItem" then
            print("FAIL:12c - got " .. typeof(Lighting.Technology))
            return
        end
        print("pass")
    ]])
    check("Lighting properties correct types", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        if typeof(workspace.Gravity) ~= "number" then
            print("FAIL:13a")
            return
        end
        if workspace.Gravity <= 0 then
            print("FAIL:13b")
            return
        end
        print("pass")
    ]])
    check("workspace.Gravity is positive number", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local ok1 = pcall(string.dump, math.abs)
        local ok2 = pcall(string.dump, print)
        local ok3 = pcall(string.dump, function() end)

        if ok1 then
            print("FAIL:14a - math.abs dump succeeded")
            return
        end
        if ok2 then
            print("FAIL:14b - print dump succeeded")
            return
        end
        if ok3 then
            print("FAIL:14c - lambda dump succeeded")
            return
        end
        print("pass")
    ]])
    check("string.dump rejects all functions", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local ok, err = pcall(error, "test error message")
        if ok then
            print("FAIL:15a")
            return
        end
        if not string.find(tostring(err), "test error message") then
            print("FAIL:15b - " .. tostring(err))
            return
        end
        print("pass")
    ]])
    check("error() message propagated", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local ok, val = pcall(function() return 42 end)
        if not ok or val ~= 42 then
            print("FAIL:16a")
            return
        end
        local ok2, err2 = pcall(function() error("boom") end)
        if ok2 then
            print("FAIL:16b")
            return
        end
        print("pass")
    ]])
    check("pcall return pattern", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local t = {3, 1, 2}
        table.sort(t)
        if t[1] ~= 1 or t[2] ~= 2 or t[3] ~= 3 then
            print("FAIL:17a - sort")
            return
        end
        local s = table.concat({"a", "b", "c"}, ",")
        if s ~= "a,b,c" then
            print("FAIL:17b - concat: " .. s)
            return
        end
        table.insert(t, 4)
        if #t ~= 4 then
            print("FAIL:17c - insert")
            return
        end
        table.remove(t, 1)
        if #t ~= 3 then
            print("FAIL:17d - remove")
            return
        end
        print("pass")
    ]])
    check("table library methods", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        if string.sub("hello", 1, 3) ~= "hel" then print("FAIL:18a") return end
        if string.byte("A") ~= 65 then print("FAIL:18b") return end
        if string.char(65) ~= "A" then print("FAIL:18c") return end
        if string.len("test") ~= 4 then print("FAIL:18d") return end
        if string.find("hello world", "world") ~= 7 then print("FAIL:18e") return end
        if string.rep("a", 3) ~= "aaa" then print("FAIL:18f") return end
        if string.reverse("abc") ~= "cba" then print("FAIL:18g") return end
        if string.upper("abc") ~= "ABC" then print("FAIL:18h") return end
        if string.lower("ABC") ~= "abc" then print("FAIL:18i") return end
        print("pass")
    ]])
    check("string library methods", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        if bit32.bxor(0xFF, 0x0F) ~= 0xF0 then print("FAIL:19a") return end
        if bit32.band(0xFF, 0x0F) ~= 0x0F then print("FAIL:19b") return end
        if bit32.bor(0xF0, 0x0F) ~= 0xFF then print("FAIL:19c") return end
        if bit32.lshift(1, 4) ~= 16 then print("FAIL:19d") return end
        if bit32.rshift(16, 4) ~= 1 then print("FAIL:19e") return end
        print("pass")
    ]])
    check("bit32 library", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local Lighting = game:GetService("Lighting")
        local tech = Lighting.Technology
        if typeof(tech) ~= "EnumItem" then
            print("FAIL:20a - got " .. typeof(tech))
            return
        end
        if type(tech.Name) ~= "string" then
            print("FAIL:20b - Name is " .. type(tech.Name))
            return
        end
        print("pass")
    ]])
    check("EnumItem has .Name", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local p = Instance.new("Part")
        p.Parent = workspace
        if typeof(p.Name) ~= "string" then
            print("FAIL:21a")
            return
        end
        if typeof(p.Parent) ~= "Instance" then
            print("FAIL:21b - got " .. typeof(p.Parent))
            return
        end
        if typeof(p.Size) ~= "Vector3" then
            print("FAIL:21c - got " .. typeof(p.Size))
            return
        end
        print("pass")
    ]])
    check("Instance property typeof()", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[

        local ref = nil
        if cloneref then
            ref = cloneref(game:GetService("AssetService"))
        end
        print("pass")
    ]])
    check("cloneref optional API doesn't crash", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local p = Instance.new("Part")
        p.Name = "TestPart"
        p.Size = Vector3.new(5, 10, 15)
        local c = p:Clone()
        if c.Name ~= "TestPart" then
            print("FAIL:23a - Name: " .. tostring(c.Name))
            return
        end
        print("pass")
    ]])
    check("Instance:Clone() preserves Name", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local fails = {}
        if typeof(1) ~= "number" then fails[#fails+1] = "number" end
        if typeof(1.5) ~= "number" then fails[#fails+1] = "number-float" end
        if typeof("x") ~= "string" then fails[#fails+1] = "string" end
        if typeof(true) ~= "boolean" then fails[#fails+1] = "boolean" end
        if typeof(nil) ~= "nil" then fails[#fails+1] = "nil" end
        if typeof({}) ~= "table" then fails[#fails+1] = "table" end
        if typeof(function() end) ~= "function" then fails[#fails+1] = "function" end
        if typeof(Vector3.new()) ~= "Vector3" then fails[#fails+1] = "Vector3" end
        if typeof(Vector2.new()) ~= "Vector2" then fails[#fails+1] = "Vector2" end
        if typeof(CFrame.new()) ~= "CFrame" then fails[#fails+1] = "CFrame" end
        if typeof(Color3.new()) ~= "Color3" then fails[#fails+1] = "Color3" end
        if typeof(UDim.new()) ~= "UDim" then fails[#fails+1] = "UDim" end
        if typeof(UDim2.new()) ~= "UDim2" then fails[#fails+1] = "UDim2" end
        if typeof(Region3.new()) ~= "Region3" then fails[#fails+1] = "Region3" end
        if typeof(BrickColor.new("Bright red")) ~= "BrickColor" then fails[#fails+1] = "BrickColor" end
        if typeof(Instance.new("Part")) ~= "Instance" then fails[#fails+1] = "Instance" end
        if typeof(math.pi) ~= "number" then fails[#fails+1] = "pi" end
        if #fails > 0 then
            print("FAIL:24 - " .. table.concat(fails, ", "))
        else
            print("pass")
        end
    ]])
    check("typeof() comprehensive", lines[1] == "pass", table.concat(lines, " | "))
end

do
    local lines = outputsOf([[
        local children = workspace:GetChildren()
        if type(children) ~= "table" then
            print("FAIL:25a")
            return
        end

        if #children < 2 then
            print("FAIL:25b - only " .. #children .. " children")
            return
        end
        print("pass")
    ]])
    check("workspace:GetChildren() populated", lines[1] == "pass", table.concat(lines, " | "))
end

print(string.format("\nantienv_comprehensive: %d passed, %d failed", passed, failed))
if failed > 0 then
    for _, line in ipairs(failures) do
        print("  FAIL  " .. line)
    end
    error("test failures")
end
