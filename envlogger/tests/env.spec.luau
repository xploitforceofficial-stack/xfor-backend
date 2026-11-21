local luau = require("@lune/luau")
local process = require("@lune/process")
local Stdlib = require("../src/env/stdlib")
local Control = require("../src/env/control")
local Datatypes = require("../src/env/datatypes")
local Spy = require("../src/core/spy")
local Trace = require("../src/core/trace")
local Sanitize = require("../src/core/sanitize")
local Sandbox = require("../src/core/sandbox")
local Report = require("../src/analysis/report")

local function renderReport(input: any): string
	return Report.render(input, { notes = true })
end

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

local function run(src: string, extra: { [string]: any }?)
	local trace = Trace.new()
	local config = { trace = trace, nest = 0 }
	local outputs: { string } = {}

	local globals = Stdlib.build()
	for key, value in pairs(Control.build({
		trace = trace,
		nest = 0,
		onOutput = function(_, text)
			outputs[#outputs + 1] = text
		end,
	})) do
		globals[key] = value
	end
	for key, value in pairs(Datatypes.build()) do
		globals[key] = value
	end
	if extra then
		for key, value in pairs(extra) do
			globals[key] = value
		end
	end

	local roots: { [string]: any } = {}
	local env = setmetatable({}, {
		__index = function(_, key)
			local known = globals[key]
			if known ~= nil then
				return known
			end
			local existing = roots[key]
			if existing then
				return existing
			end
			local root = Spy.root(key, config)
			roots[key] = root
			return root
		end,
		__newindex = function(_, key, value)
			globals[key] = value
		end,
	})

	local fn = luau.load(src, { environment = env, injectGlobals = false })
	local ok, err = pcall(fn)
	return { trace = trace, outputs = outputs, ok = ok, err = err, globals = globals }
end

do
	local r = run([[ return string.char(72, 105) ]])
	check("string.char real", r.ok, tostring(r.err))

	r = run([[ result = table.concat({"a","b","c"}, "-") ]])
	check("table.concat real", r.globals.result == "a-b-c", tostring(r.globals.result))

	r = run([[ result = string.rep("ab", 3) ]])
	check("string.rep real", r.globals.result == "ababab", tostring(r.globals.result))

	r = run([[ result = bit32.bxor(0xFF, 0x0F) ]])
	check("bit32 real", r.globals.result == 0xF0, tostring(r.globals.result))

	r = run([[ result = math.floor(7.9) ]])
	check("math.floor real", r.globals.result == 7)

	r = run([[ result = select("#", 1, 2, 3) ]])
	check("select real", r.globals.result == 3, tostring(r.globals.result))

	r = run([[ result = tostring(123) ]])
	check("tostring real", r.globals.result == "123")

	r = run([[ result = #("hello") ]])
	check("length real", r.globals.result == 5)

	r = run([[
		local out = {}
		for i = 1, 5 do out[#out+1] = string.char(64 + i) end
		result = table.concat(out)
	]])
	check("char/concat loop", r.globals.result == "ABCDE", tostring(r.globals.result))

	r = run([[ result = ("hello"):gsub("l", function(c) return "L" end) ]])
	check("gsub with callback", r.globals.result == "heLLo", tostring(r.globals.result))
end

do
	local r = run([[ result = #string.rep("x", 1e12) ]])
	check("string.rep capped", r.ok and r.globals.result <= 1000000, tostring(r.err))

	r = run([[ result = #table.create(1e12, 0) ]])
	check("table.create capped", r.ok and r.globals.result <= 1000000, tostring(r.err))
end

do
	local a = run([[ result = math.random() ]]).globals.result
	local b = run([[ result = math.random() ]]).globals.result
	check("math.random deterministic", a == b, tostring(a) .. " vs " .. tostring(b))

	local t1 = run([[ result = os.time() ]]).globals.result
	local t2 = run([[ result = os.time() ]]).globals.result
	check("os.time frozen", t1 == t2 and type(t1) == "number")
end

do
	local r = run([[ print("hello", 42) ]])
	check("print captured", r.outputs[1] == "hello\t42", tostring(r.outputs[1]))

	r = run([[ warn("careful") ]])
	check("warn captured", r.outputs[1] == "careful")

	r = run([[ result = pcall(function() error("boom") end) ]])
	check("pcall reports failure", r.globals.result == false, tostring(r.globals.result))

	r = run([[ result = pcall(function() return 1 end) ]])
	check("pcall reports success", r.globals.result == true)

	r = run([[ result = pcall(function() return nil + 1 end) ]])
	check("arith error still errors", r.globals.result == false, tostring(r.globals.result))

	r = run([[ local ok, msg = pcall(function() error("custom") end) result = msg ]])
	check("error message preserved", type(r.globals.result) == "string"
		and string.find(r.globals.result, "custom") ~= nil, tostring(r.globals.result))

	r = run([[ result = select(2, pcall(function() error({code = 7}) end)) ]])
	check("error with table value", r.ok, tostring(r.err))

	r = run([[ local ok = pcall(function() assert(false, "nope") end) result = ok ]])
	check("assert false fails", r.globals.result == false)

	r = run([[ result = assert(5, "unused") ]])
	check("assert passes value", r.globals.result == 5)

	r = run([[ result = xpcall(function() error("x") end, function(e) return "handled" end) ]])
	check("xpcall works", r.globals.result == false, tostring(r.globals.result))
end

do
	local r = run([[ local v = Vector3.new(1, 2, 3) result = v.X + v.Y + v.Z ]])
	check("Vector3 components", r.globals.result == 6, tostring(r.globals.result))

	r = run([[ local v = Vector3.new(1,2,3) + Vector3.new(1,1,1) result = v.X ]])
	check("Vector3 addition", r.globals.result == 2, tostring(r.globals.result))

	r = run([[ result = Vector3.new(1,2,3) == Vector3.new(1,2,3) ]])
	check("Vector3 equality", r.globals.result == true)

	r = run([[ result = Color3.fromRGB(255, 0, 0).R ]])
	check("Color3.fromRGB", r.globals.result == 1, tostring(r.globals.result))

	r = run([[ local c = CFrame.new(1,2,3) * CFrame.new(1,1,1) result = c.X ]])
	check("CFrame multiplication", r.globals.result == 2, tostring(r.globals.result))

	r = run([[ result = CFrame.new(5,0,0).Position.X ]])
	check("CFrame position", r.globals.result == 5, tostring(r.globals.result))

	r = run([[ result = tostring(Vector3.new(1,2,3)) ]])
	check("Vector3 tostring", r.globals.result == "1, 2, 3", tostring(r.globals.result))

	r = run([[ result = tostring(CFrame.new(1,2,3)) ]])
	check("CFrame tostring 12 components",
		r.globals.result == "1, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1", tostring(r.globals.result))

	local Serializer = require("../src/core/serializer")
	local dt = Datatypes.build()
	check("Vector3 serializes", Serializer.value(dt.Vector3.new(1, 2, 3)) == "Vector3.new(1, 2, 3)",
		Serializer.value(dt.Vector3.new(1, 2, 3)))
	check("Color3 serializes", Serializer.value(dt.Color3.new(1, 0, 0)) == "Color3.new(1, 0, 0)",
		Serializer.value(dt.Color3.new(1, 0, 0)))
	check("CFrame serializes", Serializer.value(dt.CFrame.new(0, 5, 0)) == "CFrame.new(0, 5, 0)",
		Serializer.value(dt.CFrame.new(0, 5, 0)))
end

do
	local r = run([[ local x = game:GetService("Players") ]])
	check("spy survives full env", r.ok, tostring(r.err))

	local found = false
	for _, record in ipairs(r.trace.records) do
		if string.find(record.expression, 'game:GetService("Players")', 1, true) then
			found = true
		end
	end
	check("spy traced with full env", found)

	r = run([[ result = tostring(game.Players) ]])
	check("tostring on spy", r.ok and r.globals.result == "game.Players", tostring(r.globals.result))

	r = run([[ result = type(game) ]])
	check("type of spy is table", r.globals.result == "table", tostring(r.globals.result))

	r = run([[ local t = {} t[game] = 1 result = "ok" ]])
	check("spy as table key", r.ok, tostring(r.err))
end

do
	local Sandbox = require("../src/core/sandbox")

	local r = Sandbox.run("result = checkcaller()", { timeout = 5, maxNest = 4 })
	local result = nil
	for _, rec in ipairs(r.trace.records) do
		if rec.kind == "newindex" and string.find(rec.expression, "result =", 1, true) then
			result = string.match(rec.expression, "result = (%S+)")
		end
	end
	check("checkcaller true", r.ok and result == "true", tostring(result))

	r = Sandbox.run("local c = getconnections(game.Workspace)\nif c[1] then c[1]:Disable() end\nresult = 'alive'", { timeout = 5, maxNest = 4 })
	check("getconnections usable", r.ok == true, tostring(r.err))

	local function grab(res: any, name: string): string?
		local values: { [string]: string } = {}
		local want: string? = nil
		for _, rec in ipairs(res.trace.records) do
			if rec.kind == "newindex" then
				local lhs, rhs = string.match(rec.expression, "^(%S+) = (%S+)$")
				if lhs then
					local resolved = values[rhs] or rhs
					values[lhs] = resolved
					if lhs == name then
						want = resolved
					end
				end
			end
		end
		return want
	end

	r = Sandbox.run(
		"frozen = isreadonly(table.freeze({1,2,3}))\nplain = isreadonly({})\nlocal t = {}\nsetreadonly(t, true)\nafter = isreadonly(t)",
		{ timeout = 5, maxNest = 4 }
	)
	check("isreadonly honors frozen", r.ok and grab(r, "frozen") == "true", tostring(grab(r, "frozen")))
	check("isreadonly false on plain table", grab(r, "plain") == "false", tostring(grab(r, "plain")))
	check("setreadonly(true) makes readonly", grab(r, "after") == "true", tostring(grab(r, "after")))

	r = Sandbox.run(
		"local h = game:GetService('HttpService')\n"
			.. "local a, b = h:GenerateGUID(true), h:GenerateGUID(true)\n"
			.. "distinct = a ~= b\n"
			.. "braced = string.sub(a,1,1) == '{' and string.sub(a,-1) == '}'\n"
			.. "nobrace = string.sub(h:GenerateGUID(false),1,1) ~= '{'\n"
			.. "formatok = string.match(a, '^{%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x}$') ~= nil",
		{ timeout = 5, maxNest = 4 }
	)
	check("GenerateGUID distinct", r.ok and grab(r, "distinct") == "true", tostring(grab(r, "distinct")))
	check("GenerateGUID braced by default", grab(r, "braced") == "true", tostring(grab(r, "braced")))
	check("GenerateGUID no braces when false", grab(r, "nobrace") == "true", tostring(grab(r, "nobrace")))
	check("GenerateGUID format", grab(r, "formatok") == "true", tostring(grab(r, "formatok")))

	r = Sandbox.run(
		"local m = getrawmetatable(game)\n"
			.. "istable = type(m) == 'table'\n"
			.. "stable = getrawmetatable(game) == m\n"
			.. "hasindex = type(m.__index) == 'function'",
		{ timeout = 5, maxNest = 4 }
	)
	check("getrawmetatable is table", r.ok and grab(r, "istable") == "true", tostring(grab(r, "istable")))
	check("getrawmetatable stable identity", grab(r, "stable") == "true", tostring(grab(r, "stable")))
	check("getrawmetatable has metamethods", grab(r, "hasindex") == "true", tostring(grab(r, "hasindex")))

	r = Sandbox.run("request({ Url = 'https://x.example/a', Method = 'POST' })", { timeout = 5, maxNest = 4 })
	local sawHttp = false
	for _, rec in ipairs(r.trace.records) do
		if rec.kind == "http" and string.find(rec.expression, "x.example/a", 1, true) then
			sawHttp = true
		end
	end
	check("request recorded", sawHttp)

	r = Sandbox.run("writefile('s.txt', 'print(42)')\nlocal f = loadfile('s.txt')\nif f then f() end", { timeout = 5, maxNest = 4 })
	check("loadfile runs", r.ok == true, tostring(r.err))
	local sawOutput = false
	for _, o in ipairs(r.outputs) do
		if o.text == "42" then
			sawOutput = true
		end
	end
	check("loadfile stage executed", sawOutput)
	check("loadfile stage captured", #r.stages >= 1)

	r = Sandbox.run(
		"local ok, err = pcall(function() return game:GetService('DataStoreService'):GetDataStore('k') end)\nresult = tostring(err)",
		{ timeout = 5, maxNest = 4 }
	)
	local sawDataStore = false
	for _, rec in ipairs(r.trace.records) do
		if rec.kind == "namecall" and string.find(rec.expression, "GetDataStore", 1, true) then
			sawDataStore = true
		end
	end
	check("datastore call recorded", sawDataStore)
	local dataStoreErr = nil
	for _, rec in ipairs(r.trace.records) do
		if rec.kind == "newindex" and string.find(rec.expression, "result =", 1, true) then
			dataStoreErr = rec.expression
		end
	end
	check(
		"datastore refused on client",
		dataStoreErr ~= nil and string.find(dataStoreErr, "can't be accessed from client", 1, true) ~= nil,
		tostring(dataStoreErr)
	)

	r = Sandbox.run("local e = getrenv()\nresult = type(e.loadstring)", { timeout = 5, maxNest = 4 })
	local gotType = nil
	for _, rec in ipairs(r.trace.records) do
		if rec.kind == "newindex" and string.find(rec.expression, "result =", 1, true) then
			gotType = string.match(rec.expression, 'result = "(%w+)"')
		end
	end
	check("getrenv loadstring is function", r.ok and gotType == "function", tostring(gotType))

	r = Sandbox.run(
		"ename = identifyexecutor()\ngname = getexecutorname()\ngexec = getexecutor()\ngver = getexecutorversion()",
		{ timeout = 5, maxNest = 4 }
	)
	check("identifyexecutor is Potassium", r.ok and grab(r, "ename") == '"Potassium"', tostring(grab(r, "ename")))
	check("getexecutorname is Potassium", grab(r, "gname") == '"Potassium"', tostring(grab(r, "gname")))
	check("getexecutor is Potassium", grab(r, "gexec") == '"Potassium"', tostring(grab(r, "gexec")))
	check("getexecutorversion is 2.4.3", grab(r, "gver") == '"2.4.3"', tostring(grab(r, "gver")))

	local sawIdentifyCall = false
	for _, rec in ipairs(r.trace.records) do
		if rec.kind == "call" and string.find(rec.expression, "identifyexecutor", 1, true) then
			sawIdentifyCall = true
		end
	end
	check("identifyexecutor stays trace-recorded", sawIdentifyCall)
end

do
	local Sandbox = require("../src/core/sandbox")
local Report = require("../src/analysis/report")

	local Instrument = require("../src/core/instrument")

local function render(src: string): string
	local r = Sandbox.run(src, { timeout = 5, maxNest = 4 })

	return renderReport({
			trace = r.trace,
			stages = r.stages,
			outputs = r.outputs,
			ok = r.ok,
			err = r.err,
			exhausted = r.exhausted,
			exhaustedReason = r.exhaustedReason,
			explored = r.explored,
		}, { notes = true })
	end

do
	local r = Sandbox.run([[local ok = pcall(function() error("boom") end)
print("ZZMARK", ok)]], { timeout = 5, maxNest = 4 })
	local bare = Report.render({
		trace = r.trace,
		stages = r.stages,
		outputs = r.outputs,
		ok = r.ok,
		err = r.err,
		exhausted = r.exhausted,
	})
	check("default report starts with the branded header",
		string.find(bare, "fuhed at OmniDBF .gg/odbf", 1, true) == 4, bare)
	check("default report drops the runtime warning",
		string.find(bare, "damn, this script was generated on runtime", 1, true) == nil, bare)
	check("default report drops analysis notes",
		string.find(bare, "crash trace", 1, true) == nil
			and string.find(bare, "env call log", 1, true) == nil
			and string.find(bare, "vm trace", 1, true) == nil, bare)
	check("notes=true keeps the analysis",
		string.find(render([[print("ZZN")]]), "run id", 1, true) ~= nil)
end

	local dump = render("print(tostring(game))")
	check("tostring(instance) is userdata", string.find(dump, "userdata: 0x%x+") ~= nil, dump)

	dump = render("if tostring(game.Players.LocalPlayer) == game.Players.LocalPlayer.Name then print('pass') else print('no') end")
	check("tostring(player) == player.Name", string.find(dump, "print(\"pass\")", 1, true) ~= nil, dump)
	dump = render("print(tostring(workspace.Part))")
	check("tostring resolves instance Name", string.find(dump, "print(\"Part\")", 1, true) ~= nil, dump)
	dump = render("print(tostring(game.Players))")
	check("tostring resolves service Name", string.find(dump, "print(\"Players\")", 1, true) ~= nil, dump)

	dump = render("if Instance.new('Part'):IsA('BasePart') then print('basepart') end")
	check("IsA BasePart", string.find(dump, "print(\"basepart\")", 1, true) ~= nil, dump)
	dump = render("if game:IsA('DataModel') then print('dm') end")
	check("IsA DataModel", string.find(dump, "print(\"dm\")", 1, true) ~= nil, dump)
	dump = render("if game.Players.LocalPlayer:IsA('Player') then print('plr') end")
	check("IsA Player", string.find(dump, "print(\"plr\")", 1, true) ~= nil, dump)

	dump = render("if game.Players.LocalPlayer.DisplayName ~= game.Players.LocalPlayer.Name then print('distinct') else print('same') end")
	check("DisplayName differs from Name", string.find(dump, "print(\"distinct\")", 1, true) ~= nil, dump)

	dump = render("if game.Players:GetPlayers()[1] == game.Players.LocalPlayer then print('same') end")
	check("GetPlayers[1] is LocalPlayer", string.find(dump, "print(\"same\")", 1, true) ~= nil, dump)

	dump = render("local p = Instance.new('Part')\np.Anchored = true\nif p.Anchored then print('write') end")
	check("instance property write sticks", string.find(dump, "print(\"write\")", 1, true) ~= nil, dump)

	dump = render("print(workspace.Parent)")
	check("workspace.Parent is game", string.find(dump, "print(game)", 1, true) ~= nil, dump)

	dump = render("local a = Instance.new('Folder', game.ReplicatedStorage)\nprint(a.Parent)")
	check("Instance.new keeps parent arg", string.find(dump, 'Instance.new("Folder", game:GetService("ReplicatedStorage"))', 1, true) ~= nil, dump)
	check("parent read uses local name", string.find(dump, "local _ = a.Parent", 1, true) ~= nil, dump)

	dump = render("local b = Instance.new('Part')\nb.Parent = workspace\nprint(#workspace:GetDescendants())")
	check("parent write uses local name", string.find(dump, "b.Parent = game:GetService(\"Workspace\")", 1, true) ~= nil, dump)
	check("descendants count grows", string.find(dump, "print(9)", 1, true) ~= nil, dump)

	dump = render("print(Instance.new('Part').Parent)")
	check("unparented instance Parent is nil", string.find(dump, "print(nil)", 1, true) ~= nil, dump)

	dump = render("print(game)")
	check("print(spy) unquoted", string.find(dump, "print(game)", 1, true) ~= nil
		and string.find(dump, 'print("game")', 1, true) == nil, dump)

	dump = render("print(123)\nprint('hi')")
	check("print(number) unquoted", string.find(dump, "print(123)", 1, true) ~= nil
		and string.find(dump, 'print("123")', 1, true) == nil, dump)
	check("print(string) quoted", string.find(dump, 'print("hi")', 1, true) ~= nil, dump)

	dump = render("a = 1\nprint(a)")
	check("print resolves global name", string.find(dump, "a = 1", 1, true) ~= nil
		and string.find(dump, "print(a)", 1, true) ~= nil, dump)

	dump = render("if game.SomeNonsense then print('bad') else print('nil ok') end")
	check("game.Unknown is nil", string.find(dump, "nil ok", 1, true) ~= nil, dump)
	dump = render("if workspace.SomeNonsense then print('bad') else print('nil ok') end")
	check("workspace.Unknown is nil", string.find(dump, "nil ok", 1, true) ~= nil, dump)

	dump = render("print(workspace.Camera.FieldOfView)")
	check("camera field of view concrete", string.find(dump, "print(70)", 1, true) ~= nil, dump)
	dump = render("print(workspace.Part.Size)")
	check("part size concrete", string.find(dump, "Vector3.new(4, 1.2, 4)", 1, true) ~= nil, dump)

	dump = render('local p = workspace:WaitForChild("Part")\nprint(p.Position)')
	check("namecall traced", string.find(dump, ':WaitForChild("Part")', 1, true) ~= nil, dump)

	dump = render('local p = game:WaitForChild("Players")\nprint(p:IsA("Players"))')
	check("game WaitForChild resolves", string.find(dump, 'game:WaitForChild("Players")', 1, true) ~= nil
		and string.find(dump, "print(true)", 1, true) ~= nil, dump)
	dump = render("print(game:IsA('DataModel'))")
	check("game IsA DataModel", string.find(dump, "print(true)", 1, true) ~= nil, dump)
	dump = render("print(workspace.Camera:IsA('Camera'))\nprint(workspace.Camera:IsA('Part'))")
	check("instance IsA true and false", string.find(dump, "print(true)", 1, true) ~= nil
		and string.find(dump, "print(false)", 1, true) ~= nil, dump)

	dump = render('local x = workspace:FindFirstChild("NotThere")\nprint(x and "found" or "nil")')
	check("FindFirstChild unknown returns nil", string.find(dump, 'print("nil")', 1, true) ~= nil, dump)

	dump = render('for _, v in ipairs(workspace:GetChildren()) do print(v.Name) end')
	check("GetChildren lists children", string.find(dump, ':GetChildren()', 1, true) ~= nil
		and string.find(dump, 'print("Camera")', 1, true) ~= nil, dump)

	dump = render('print(game:GetService("Players"):FindFirstChild("LocalPlayer").Name)')
	check("service FindFirstChild resolves child", string.find(dump, 'print%("(' .. "[%w_]+" .. ')"%)') ~= nil, dump)

	dump = render('print(game:GetService("Lighting").Brightness)')
	check("Lighting.Brightness concrete", string.find(dump, "print(1)", 1, true) ~= nil, dump)
	dump = render('print(game:GetService("Lighting").TimeOfDay)')
	check("Lighting.TimeOfDay concrete", string.find(dump, 'print("14:00:00")', 1, true) ~= nil, dump)
	dump = render('print(game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.Q))')
	check("UserInputService:IsKeyDown concrete", string.find(dump, "print(false)", 1, true) ~= nil, dump)
	dump = render('game:GetService("RunService").Heartbeat:Connect(function() print("beat") end)')
	check("service event connect traced", string.find(dump, "Heartbeat:Connect", 1, true) ~= nil, dump)

	dump = render('game:GetService("Workspace").DescendantAdded:Connect(function() end)\ngame:GetService("ReplicatedStorage").ChildAdded:Connect(function() end)\nprint("ok")')
	check("service instance-signals resolve", string.find(dump, 'print("ok")', 1, true) ~= nil
		and string.find(dump, "runtime error", 1, true) == nil, dump)
	dump = render('game:GetService("Lighting"):GetPropertyChangedSignal("ClockTime"):Connect(function() end)\nprint("ok")')
	check("service GetPropertyChangedSignal resolves", string.find(dump, 'print("ok")', 1, true) ~= nil
		and string.find(dump, "runtime error", 1, true) == nil, dump)
	dump = render('game:BindToClose(function() end)\nprint("ok")')
	check("game:BindToClose no-ops", string.find(dump, 'print("ok")', 1, true) ~= nil
		and string.find(dump, "runtime error", 1, true) == nil, dump)
	dump = render('game:GetService("TweenService"):Tween(workspace.Part, TweenInfo.new(1), { Position = Vector3.new(0, 10, 0) })')
	check("TweenService:Tween traced", string.find(dump, ':Tween(game:GetService("Workspace").Part', 1, true) ~= nil, dump)
	dump = render('for _, v in ipairs(game:GetService("CollectionService"):GetTagged("x")) do print(v) end')
	check("CollectionService:GetTagged traced", string.find(dump, ':GetTagged("x")', 1, true) ~= nil
		and string.find(dump, "runtime error", 1, true) == nil, dump)
	dump = render('local x = game:GetService("Players").SomeNonsense\nprint(x and "truthy" or "nil")')
	check("unknown service member is spy", string.find(dump, 'print("truthy")', 1, true) ~= nil, dump)

	dump = render([[
		local RS = game:GetService("RunService")
		local beats, lastDt = 0, 0
		RS.Heartbeat:Connect(function(dt)
			beats += 1
			lastDt = dt
		end)
		task.wait(0.1)
		print(beats > 0 and lastDt > 0)
	]])
	check("frame scheduler fires Heartbeat with dt", string.find(dump, 'print(true)', 1, true) ~= nil, dump)

	dump = render([[
		local RS = game:GetService("RunService")
		local a, b = nil, nil
		local n = 0
		RS.Heartbeat:Connect(function(dt)
			n += 1
			if n == 1 then a = os.clock() else b = os.clock() end
		end)
		task.wait()
		task.wait()
		print(a ~= b)
	]])
	check("heartbeat timestamps differ", string.find(dump, 'print(true)', 1, true) ~= nil, dump)

	dump = render([[
		local ev = Instance.new("BindableEvent")
		local fired = false
		ev.Event:Connect(function() fired = true end)
		task.wait(0.2)
		local survivedFrames = not fired
		ev:Fire(nil)
		print(survivedFrames and fired)
	]])
	check("non-frame signals skip frames", string.find(dump, 'print(true)', 1, true) ~= nil, dump)

	dump = render("c=0\nwhile task.wait(1) do\nc+=1\nif c == 5 then break end\nend\nprint'a'")
	check("while header synthesized", string.find(dump, "while true do", 1, true) ~= nil, dump)
	check("wait folded into body", string.find(dump, "task.wait(1)", 1, true) ~= nil, dump)
	check("iterations collapsed to one", string.find(dump, "c = 1", 1, true) == nil
		and string.find(dump, "c = 4", 1, true) == nil, dump)
	check("exit-if truthy kept", string.find(dump, "--did ran", 1, true) ~= nil, dump)
	check("break synthesized", string.find(dump, "break", 1, true) ~= nil, dump)
	check("no explored spam for loop exit-if", select(2, string.gsub(dump, "explored branch: c == 5", "")) == 0
		or select(2, string.gsub(dump, "explored branch: c == #", "")) == 0, dump)

	dump = render('print(game.AccountService ~= nil)')
	check("new service shorthand resolves", string.find(dump, "print(true)", 1, true) ~= nil, dump)
	dump = render('print(game:GetService("GeometryService"):GetEdgesForPartAsync())')
	check("new service method traced", string.find(dump, ':GetEdgesForPartAsync()', 1, true) ~= nil
		and string.find(dump, "print({})", 1, true) ~= nil, dump)

	dump = render('local p = Instance.new("Part")\nprint(p.Anchored, p.Transparency)')
	check("Instance.new Part defaults", string.find(dump, "print(false, 0)", 1, true) ~= nil, dump)
	dump = render('local t = Instance.new("Tool")\nprint(t.RequiresHandle)\nprint(t.Handle.Size)')
	check("Instance.new Tool handle", string.find(dump, "print(true)", 1, true) ~= nil
		and string.find(dump, "Vector3.new(4, 4, 4)", 1, true) ~= nil, dump)
	dump = render('local v = Instance.new("IntValue")\nv.Value = 5\nprint(v.Value)')
	check("Instance.new value read/write", string.find(dump, "print(5)", 1, true) ~= nil, dump)
	dump = render('local f = Instance.new("Frame")\nprint(f.Size)')
	check("Instance.new Frame size", string.find(dump, "UDim2.new(0, 100, 0, 100)", 1, true) ~= nil, dump)

	dump = render([[local e = getfenv()
print(e.tonumber, e.string, e.string, e.table)]])
	check("getfenv traced", string.find(dump, "getfenv()", 1, true) ~= nil, dump)
	check("env reads summarized", string.find(dump, "--[[ getfenv() reads: string (x2), table, tonumber ]]", 1, true) ~= nil, dump)
	check("env reads not a wall", string.find(dump, "local _ = getfenv().string", 1, true) == nil
		and string.find(dump, "local _ = getfenv().tonumber", 1, true) == nil, dump)
	check("env reads carry receiver", string.find(dump, "e = getfenv()", 1, true) ~= nil, dump)

	dump = render([[_OgPfGznCLYMi = "This file was protected with MoonSec V3"
local d = getfenv()
d.SomeVar = 42]])
	check("env write via getfenv", string.find(dump, "getfenv()._OgPfGznCLYMi = \"This file was protected with MoonSec V3\"", 1, true) ~= nil
		and string.find(dump, "getfenv().SomeVar = 42", 1, true) ~= nil, dump)
	dump = render("abc = 1\nprint(1)")
	check("plain global write stays plain", string.find(dump, "abc = 1", 1, true) ~= nil
		and string.find(dump, "getfenv().abc", 1, true) == nil, dump)

	dump = render("local x = _G.tonumber('7')\nprint(x)")
	check("_G reads summarized", string.find(dump, "--[[ _G reads: tonumber ]]", 1, true) ~= nil
		and string.find(dump, "getfenv().tonumber", 1, true) == nil, dump)

	dump = render("local w = getfenv()")
	check("getfenv local capture", string.find(dump, "w = getfenv()", 1, true) ~= nil
		and string.find(dump, "w = {}", 1, true) == nil, dump)

	dump = render("print(workspace.SpawnLocation.Neutral)\nprint(workspace.AirDensity)")
	check("workspace spawnlocation", string.find(dump, "print(false)", 1, true) ~= nil
		and string.find(dump, "print(1.2)", 1, true) ~= nil, dump)

	dump = render([[local tb = Instance.new("TextBox")
print(tb.PlaceholderText, tb.TextEditable)]])
	check("Instance.new TextBox", string.find(dump, "print(\"\", true)", 1, true) ~= nil, dump)
	dump = render([[local r = Instance.new("RemoteEvent")
print(r:IsA("RemoteEvent"))]])
	check("Instance.new RemoteEvent IsA", string.find(dump, "print(true)", 1, true) ~= nil, dump)
	dump = render([[local h = Instance.new("HingeConstraint")
print(h.Enabled, h.ActuatorType)]])
	check("Instance.new HingeConstraint", string.find(dump, "print(true, \"None\")", 1, true) ~= nil, dump)
	dump = render([[local m = Instance.new("SpecialMesh")
print(m.MeshType)]])
	check("Instance.new SpecialMesh", string.find(dump, "print(\"FileMesh\")", 1, true) ~= nil, dump)
	dump = render([[local l = Instance.new("PointLight")
print(l.Range, l.Brightness)]])
	check("Instance.new PointLight", string.find(dump, "print(10, 1)", 1, true) ~= nil, dump)
	dump = render([[local pe = Instance.new("ParticleEmitter")
print(pe.Lifetime)]])
	check("Instance.new ParticleEmitter", string.find(dump, "NumberRange.new(2, 4)", 1, true) ~= nil, dump)

	do
		local infos: { any } = {}
		local r = Sandbox.run([[local f = loadstring("print('x')")
f()
local i = 0
while i < 300 do i += 1 end]], {
			timeout = 5,
			maxNest = 4,
			onProgress = function(info: any)
				infos[#infos + 1] = info
			end,
		})
		check("progress fired", #infos >= 3, "got " .. tostring(#infos))
		check("progress has ops", (infos[1] and infos[1].ops or 0) > 0, dump)
		local last = infos[#infos]
		check("progress reports stages", last ~= nil and (last.stages or 0) >= 1, tostring(last and last.stages))
		check("progress ok run not exhausted", last ~= nil and last.exhausted == false, tostring(last and last.exhausted))
		local sawStage = false
		for _, info in ipairs(infos) do
			if type(info.activity) == "string" and string.find(info.activity, "loadstring stage captured", 1, true) then
				sawStage = true
			end
		end
		check("progress logs stage capture", sawStage)
		check("progress run ok", r.ok == true)
	end

	do
		local r = Sandbox.run([[local f = loadstring("return 1")
local g = loadstring(tostring(f))
result = (g == nil)]], { timeout = 5, maxNest = 4 })
		local resultText = nil
		for _, rec in ipairs(r.trace.records) do
			if rec.kind == "newindex" and string.find(rec.expression, "result =", 1, true) then
				resultText = rec.expression
			end
		end
		check("loadstring of tostring(fn) returns nil", r.ok and resultText ~= nil
			and string.find(resultText, "result = true", 1, true) ~= nil, tostring(resultText))
		local leakDump = renderReport({
			trace = r.trace,
			stages = r.stages,
			outputs = r.outputs,
			ok = r.ok,
			err = r.err,
			exhausted = r.exhausted,
			exhaustedReason = r.exhaustedReason,
			explored = r.explored,
		})
		check("no function pointer leak in dump", string.find(leakDump, "function: 0x", 1, true) == nil, leakDump)
		local stages = r.stages or {}
		local hasDecoy = false
		for _, stage in ipairs(stages) do
			if type(stage.source) == "string" and string.find(stage.source, "function:", 1, true) then
				hasDecoy = true
			end
		end
		check("decoy never recorded as stage", not hasDecoy)
	end

	do
		local r = Sandbox.run([[local s = string.rep("A", 300)
buffer.fromstring(s)]], { timeout = 5, maxNest = 4 })
		local bufDump = renderReport({
			trace = r.trace,
			stages = r.stages,
			outputs = r.outputs,
			ok = r.ok,
			err = r.err,
			exhausted = r.exhausted,
			exhaustedReason = r.exhaustedReason,
			explored = r.explored,
		})
		check("buffer stage suppresses nothing-observable note", string.find(bufDump, "nothing observable", 1, true) == nil, bufDump)

		check("buffer stage renders clean", string.find(bufDump, "recovered program", 1, true) == nil
			and string.find(bufDump, "stage %d") == nil, bufDump)
	end

	do
		local r = Sandbox.run([[local e = getfenv()
local _ = e.assert
local _ = e.ipairs
local _ = e.pairs
return e]], { timeout = 5, maxNest = 4 })
		local probeDump = renderReport({
			trace = r.trace,
			stages = r.stages,
			outputs = r.outputs,
			ok = r.ok,
			err = r.err,
			exhausted = r.exhausted,
			exhaustedReason = r.exhaustedReason,
			explored = r.explored,
			vmTrace = r.vmTrace,
			vmTraceCapped = r.vmTraceCapped,
		})
		check("env-probe-only run is labelled no-observable-behavior",
			string.find(probeDump, "nothing observable", 1, true) ~= nil, probeDump)
	end

	do
		local r = Sandbox.run([[local _ = getfenv()
print("real behavior")]], { timeout = 5, maxNest = 4 })
		local actDump = renderReport({
			trace = r.trace,
			stages = r.stages,
			outputs = r.outputs,
			ok = r.ok,
			err = r.err,
			exhausted = r.exhausted,
			exhaustedReason = r.exhaustedReason,
			explored = r.explored,
			vmTrace = r.vmTrace,
			vmTraceCapped = r.vmTraceCapped,
		})
		check("observable behavior suppresses no-observable note",
			string.find(actDump, "nothing observable", 1, true) == nil, actDump)
	end

	dump = render("print(game.Players.LocalPlayer.Character.Humanoid.Health)")
	check("character health concrete", string.find(dump, "print(100)", 1, true) ~= nil, dump)
	dump = render("if game.Players.LocalPlayer.Character.Humanoid.Health > 0 then print('alive') end")
	check("character health comparable", string.find(dump, 'print("alive")', 1, true) ~= nil, dump)

	dump = render([[local a = game
local b = "Players"
local c = "LocalPlayer"
local d = "Name"
local e = a[b]
local f = e[c]
local h = f[d]
local i = e:FindFirstChild(c)
local j = i and i[d]
local k = a:GetService(b)
local l = k:FindFirstChild(c)
local m = l and l[d]
local n = a[b][c]
local o = n[d]
local p = a:FindFirstChild(b)
local q = p and p:FindFirstChild(c)
local r = q and q:FindFirstChild(d)
local s = r and r.Value
print(h, j, m, o, s)]])
	check("multi chain runs clean", string.find(dump, "runtime error", 1, true) == nil, dump)
	check("multi chain finds services", string.find(dump, 'game:FindFirstChild("Players")', 1, true) ~= nil
		and string.find(dump, ':FindFirstChild("LocalPlayer")', 1, true) ~= nil, dump)

	dump = render('for i = 1, 5 do print("smth") end')
	check("repeat collapse", string.find(dump, 'print("smth") --[[ x5 ]]', 1, true) ~= nil, dump)

	dump = render([[
local start = tick()
repeat
    task.wait(0)
until tick() - start > 0.05
]])
	check("interleaved pair collapse", string.find(dump, "task%.wait%(0%) %-%-%[%[ x%d+ %]%]") ~= nil, dump)

	dump = render("local a = {}\na.a = 1\nprint(a.a)\nprint(a)")
	check("local table logged", string.find(dump, "a = {}", 1, true) ~= nil, dump)
	check("local print resolves", string.find(dump, "print(a)", 1, true) ~= nil
		and string.find(dump, "print({ a = 1 })", 1, true) == nil, dump)

	dump = render("local x = 5\nprint(x)")
	check("local scalar logged", string.find(dump, "x = 5", 1, true) ~= nil
		and string.find(dump, "print(x)", 1, true) ~= nil, dump)

	dump = render("pcall(function() game:Destroy() end)")
	check("game:Destroy traced", string.find(dump, "game:Destroy()", 1, true) ~= nil, dump)
	local res = Sandbox.run("game:Destroy()", { timeout = 5, maxNest = 4 })
	check("game:Destroy refused", res.ok == false and string.find(tostring(res.err), "destroying", 1, true) ~= nil, tostring(res.err))

	local blocked = Sandbox.run(
		'print(pcall(function() game:HttpGet("http://127.0.0.1:8080/x") end))',
		{ timeout = 5, maxNest = 4 }
	)
	check("localhost fetch refused", blocked.outputs[#blocked.outputs] ~= nil
		and string.find(blocked.outputs[#blocked.outputs].text, "^false", 1) ~= nil
		and string.find(blocked.outputs[#blocked.outputs].text, "private address", 1, true) ~= nil,
		tostring(blocked.outputs[#blocked.outputs] and blocked.outputs[#blocked.outputs].text))

	local websocket = Sandbox.run(
		'print(pcall(function() WebSocket.connect("ws://192.168.0.5:9999") end))',
		{ timeout = 5, maxNest = 4 }
	)
	check("private websocket refused", websocket.outputs[#websocket.outputs] ~= nil
		and string.find(websocket.outputs[#websocket.outputs].text, "^false", 1) ~= nil,
		tostring(websocket.outputs[#websocket.outputs] and websocket.outputs[#websocket.outputs].text))

	local public = Sandbox.run(
		'print(pcall(function() game:HttpGet("https://example.com/x") end))',
		{ timeout = 5, maxNest = 4 }
	)
	check("public fetch allowed", public.outputs[#public.outputs] ~= nil and public.outputs[#public.outputs].text == "true",
		tostring(public.outputs[#public.outputs] and public.outputs[#public.outputs].text))

	dump = render("print(game.Players.LocalPlayer.Name)")
	local name = string.match(dump, 'print%("([%w_]+)"%)')
	check("player name random shape", name ~= nil and #name >= 5, dump)
	local dump2 = render("print(game.Players.LocalPlayer.Name)")
	check("player name deterministic", string.find(dump, name, 1, true) ~= nil
		and string.find(dump2, name, 1, true) ~= nil)

	dump = render("if game.Players:GetPlayers()[1] ~= nil then print('yay') end")
	check("GetPlayers()[1] is a player", string.find(dump, 'print("yay")', 1, true) ~= nil, dump)
	dump = render("print(game:GetService('Players'):GetPlayers()[1].Name)")
	check("GetPlayers()[1].Name is the player name", string.find(dump, 'print%("(' .. "[%w_]+" .. ')"%)') ~= nil, dump)
	local gotRosterName = string.match(dump, 'print%("([%w_]+)"%)')
	check("roster name matches LocalPlayer", gotRosterName ~= nil and gotRosterName == name, dump)

	dump = render("print(type(game))")
	check("type(game) is userdata", string.find(dump, 'print("userdata")', 1, true) ~= nil, dump)
	dump = render("print(type(workspace.Part))")
	check("type(instance) is userdata", string.find(dump, 'print("userdata")', 1, true) ~= nil, dump)
	dump = render("print(type({ 1 }))")
	check("type(table) stays table", string.find(dump, 'print("table")', 1, true) ~= nil, dump)

	dump = render("print(#game)")
	check("len instance errors", string.find(dump, "attempt to get length of a userdata value") ~= nil, dump)
	check("len error clean", string.find(dump, "spy:") == nil and string.find(dump, "%a:\\") == nil, dump)

	dump = render("print(pcall(function() return #game end))")
	check("pcall'd len error clean", string.find(dump, 'print(false, "attempt to get length of a userdata value', 1, true) ~= nil, dump)
	check("pcall'd len error no leak", string.find(dump, "spy:") == nil and string.find(dump, ":\\") == nil, dump)

	dump = render("print(#game.Players:GetPlayers()[1])")
	check("len player errors", string.find(dump, "attempt to get length of a userdata value") ~= nil, dump)

	dump = render("print(pcall(function() return game:Destroy() end))")
	check("game:Destroy refused", string.find(dump, "game:Destroy()", 1, true) ~= nil
		and string.find(dump, 'print(false, "', 1, true) ~= nil, dump)

	do
		local cases = {
			{ src = "game.Players.LocalPlayer:Kick('abc')\nprint('after')", label = "LocalPlayer:Kick" },
			{ src = "game.Players.LocalPlayer:KickFor(60)\nprint('after')", label = "LocalPlayer:KickFor" },
			{ src = "game.Players.LocalPlayer:Destroy()\nprint('after')", label = "LocalPlayer:Destroy" },
			{ src = "game.Players:GetPlayers()[1]:Kick('bye')\nprint('after')", label = "GetPlayers()[1]:Kick" },
			{ src = "workspace:ClearAllChildren()\nprint('after')", label = "workspace:ClearAllChildren" },
			{ src = "workspace:Destroy()\nprint('after')", label = "workspace:Destroy" },
			{ src = "game:GetService('Players'):ClearAllChildren()\nprint('after')", label = "Players:ClearAllChildren" },
		}
		for _, case in ipairs(cases) do
			local r = Sandbox.run(case.src, { timeout = 5, maxNest = 4 })
			local out = renderReport({
				trace = r.trace,
				stages = r.stages,
				outputs = r.outputs,
				ok = r.ok,
				err = r.err,
				exhausted = r.exhausted,
				exhaustedReason = r.exhaustedReason,
				explored = r.explored,
			})
		check(case.label .. " errors with joke", r.ok == false
			and string.find(tostring(r.err), "permanent", 1, true) ~= nil
			or string.find(tostring(r.err), "sandbox", 1, true) ~= nil, tostring(r.err))
			check(case.label .. " kills script", string.find(out, 'print("after")', 1, true) == nil, out)
		end
	end

	dump = render("local p = Instance.new('Part')\np:Destroy()\nprint('ran')")
	check("instance Destroy silent no-op", string.find(dump, 'print("ran")', 1, true) ~= nil, dump)

	dump = render("print(game.Players.MaxPlayers)")
	check("Players.MaxPlayers concrete", string.find(dump, "print(100)", 1, true) ~= nil, dump)
	dump = render("print(workspace.Camera.NearPlaneZ)")
	check("Camera.NearPlaneZ concrete", string.find(dump, "print(0.1)", 1, true) ~= nil, dump)

	dump = render("print(#game.Players:GetPlayers()[1])")
	check("read prefixed with local _", string.find(dump, "local _ = game.Players", 1, true) ~= nil
		and string.find(dump, "game:GetService(\"Players\"):GetPlayers()", 1, true) ~= nil
		and string.find(dump, "local _ = game:GetService(\"Players\"):GetPlayers()", 1, true) == nil, dump)

	dump = render("game:Destroy()")
	check("statement call bare", string.find(dump, "game:Destroy()", 1, true) ~= nil
		and string.find(dump, "local _ = game:Destroy()", 1, true) == nil, dump)

	dump = render("local x = game:GetService('Players')\nprint(x)")
	check("local capture folds call", string.find(dump, "x = game:GetService(\"Players\")", 1, true) ~= nil
		and string.find(dump, "local _ = game:GetService(\"Players\")", 1, true) == nil, dump)

	dump = render("if game.Players ~= nil then print('yay') end")
	check("if condition spied", string.find(dump, "if game.Players ~= nil then --did ran", 1, true) ~= nil, dump)
	check("if condition read folded", string.find(dump, "local _ = game.Players", 1, true) == nil, dump)
	dump = render("local n = 5\nif n > 3 then print('big') end")
	check("concrete branch spied", string.find(dump, "if n > 3 then --did ran", 1, true) ~= nil, dump)
	dump = render("local n = 1\nif n > 3 then print('big') else print('small') end")
	check("falsy branch spied", string.find(dump, "if n > 3 then --didnt ran", 1, true) ~= nil
		and string.find(dump, 'print("small")', 1, true) ~= nil, dump)

	dump = render("for i = 1, 4 do if i > 2 then print('big') end end")
	check("branch run annotated", string.find(dump, "if i > 2 then --didnt ran --[[ x2 ]]", 1, true) ~= nil, dump)

	dump = render("local n = 2\nif n == 1 then print('one') elseif n == 2 then print('two') end")
	check("elseif spied", string.find(dump, "elseif n == 2 then --did ran", 1, true) ~= nil, dump)

	check("elseif not double if", string.find(dump, "\nif n == 2 then --did ran", 1, true) == nil, dump)

	dump = render("if game and\n\tworkspace then print('both') end")
	check("multiline cond collapsed", string.find(dump, "if game and workspace then --did ran", 1, true) ~= nil, dump)

	local botErr = [[C:\Users\Sandr\OneDrive\Desktop\EnviromentLogger\src\bot\commands:798: attempt to index nil with 'ops'
stack traceback:
	C:\Users\Sandr\OneDrive\Desktop\EnviromentLogger\src\bot\commands:1053: in function 'handler'
	[string "stage"]:1: in main chunk]]
	local clean = Sanitize.message(botErr)
	check("host path stripped from error", string.find(clean, "Sandr", 1, true) == nil
		and string.find(clean, "EnviromentLogger", 1, true) == nil
		and string.find(clean, "C:\\Users", 1, true) == nil, clean)
	check("bot module location stripped", string.find(clean, "commands:", 1, true) == nil, clean)
	check("error text survives", string.find(clean, "attempt to index nil with 'ops'", 1, true) ~= nil, clean)

	check("user chunk location preserved", string.find(clean, '[string "stage"]', 1, true) ~= nil, clean)

	dump = render("print(\u{201C}h\u{201D})")
	check("smart quotes recovered", string.find(dump, 'print("h")', 1, true) ~= nil, dump)

	dump = render("print()\nprint('hi')")
	check("print() no args", string.find(dump, "print()", 1, true) ~= nil, dump)

	dump = render("collectgarbage('collect')\nprint(type(collectgarbage))")
	check("collectgarbage real", string.find(dump, 'print("function")', 1, true) ~= nil, dump)

	dump = render("rconsoleprint('hello from console')")
	check("rconsole captured", string.find(dump, 'rconsoleprint("hello from console")', 1, true) ~= nil, dump)

	dump = render("if type(os) == 'table' and type(os.execute) == 'function' then print('vuln') else print('safe') end")

		check("os.execute probe falsy", string.find(dump, 'print("safe")', 1, true) ~= nil
			and string.find(dump, "--didnt ran", 1, true) ~= nil, dump)
		check("os.execute vuln only in explored", string.find(dump, 'print("vuln")', 1, true) ~= nil
			and string.find(dump, "explored branch", 1, true) == nil, dump)

	dump = render("local x = os and os.execute\nprint('execute exists:', x ~= nil)")
	check("os.execute reads nil", string.find(dump, "print(\"execute exists:\", false)", 1, true) ~= nil, dump)
	check("os.execute read stays silent", string.find(dump, "fuck off", 1, true) == nil, dump)

	dump = render("os.execute('whoami')")
	check("os.execute call is engine error", string.find(dump, "attempt to call a nil value", 1, true) ~= nil, dump)
	check("os.execute call no joke", string.find(dump, "fuck off", 1, true) == nil, dump)

	dump = render("local n = 0 for _ in pairs(os) do n = n + 1 end print(n + 0)")
	check("os hides hostile keys", string.find(dump, "print(4)", 1, true) ~= nil, dump)

	dump = render("print(type(io), type(package), type(process), type(fs), type(net))")
	check("host modules nil", string.find(dump, 'print("nil", "nil", "nil", "nil", "nil")', 1, true) ~= nil, dump)

	dump = render("pcall(function() return readfile('/etc/passwd') end)")
	check("readfile host path refused", string.find(dump, "file api", 1, true) ~= nil, dump)
	dump = render("pcall(function() return readfile('C:/Windows/system.ini') end)")
	check("readfile drive path refused", string.find(dump, "file api", 1, true) ~= nil, dump)

	dump = render("pcall(function() return loadfile('/etc/hosts') end)")
	check("loadfile host path refused", string.find(dump, "file api", 1, true) ~= nil, dump)

	dump = render("print(isfile('/etc/passwd'))")
	check("isfile host path false", string.find(dump, "print(false)", 1, true) ~= nil, dump)

	dump = render("abc = 1 print(1)")
	check("literal number not over-resolved", string.find(dump, "abc = 1", 1, true) ~= nil
		and string.find(dump, "print(1)", 1, true) ~= nil
		and string.find(dump, "print(abc)", 1, true) == nil, dump)
	dump = render("abc = 1 print(abc)")
	check("variable reference keeps its name", string.find(dump, "print(abc)", 1, true) ~= nil, dump)

	dump = render("if game then print('A') else print('B') end")
	check("primary branch side", string.find(dump, 'print("A")', 1, true) ~= nil, dump)
	check("explored opposite side", string.find(dump, 'print("B")', 1, true) ~= nil
		and string.find(dump, "else", 1, true) ~= nil
		and string.find(dump, "explored branch", 1, true) == nil, dump)

		dump = render("local x = 5 if x > 3 then print('big') else print('small') end")
		check("concrete branch explored", string.find(dump, 'print("big")', 1, true) ~= nil
			and string.find(dump, 'print("small")', 1, true) ~= nil
			and string.find(dump, "explored branch", 1, true) == nil, dump)

	dump = render([[local f = function() while 1 do print"skid" end end
local ok = pcall(function()
    for _, v in game:GetChildren() do
        local o, x = pcall(function() return v.Sandboxed end)
        if o and x ~= true and x ~= false then f() end
    end
end)
print("anti-env clean")]])
	check("Sandboxed reads false", string.find(dump, "--[[ .Sandboxed read across", 1, true) ~= nil, dump)
	check("anti-env not triggered", string.find(dump, 'print("skid")', 1, true) == nil
		and string.find(dump, 'print("anti-env clean")', 1, true) ~= nil, dump)

	dump = render([[
local fired = 0
local function skid() fired += 1 end
local ok
ok = pcall(function() local m=game:GetService"MaterialService" if m.Use2022Materials~=true and m.Use2022Materials~=false then skid() end end)
ok = pcall(function() local t=game:GetService"TextChatService" local w,i,c,b=t:FindFirstChild"ChatWindowConfiguration",t:FindFirstChild"ChatInputBarConfiguration",t:FindFirstChild"ChannelTabsConfiguration",t:FindFirstChild"BubbleChatConfiguration" if not w or not i or not c or not b then skid() end if not i.TargetTextChannel or i.TargetTextChannel.Name~="RBXGeneral"or b.AdorneeName~="HumanoidRootPart"then skid() end end)
ok = pcall(function() local t=game:GetService"TextChatService" local p=t.PlatformIntegratedChat if not p or(p.Name~="Default"and p.Name~="Disabled"and p.Name~="Enabled")then skid() end end)
ok = pcall(function() for _,v in workspace:GetDescendants()do if v:IsA"BasePart"and v.Anchored and v.AssemblyMass~=math.huge then skid() end end end)
ok = pcall(function() local tr=workspace:FindFirstChildOfClass"Terrain" if not tr or typeof(tr.Size)~="Vector3"or not tr.CanCollide or not tr.Anchored then skid() end end)
ok = pcall(function() local h=game.Players.LocalPlayer.Character.HumanoidRootPart local cam=workspace.CurrentCamera local a,b=false,false local x=h:GetPropertyChangedSignal"CFrame":Connect(function()a=true end) local y=cam:GetPropertyChangedSignal"CFrame":Connect(function()b=true end) h.CFrame+=Vector3.yAxis*.25 local q=Instance.new"Part"q.Position=Vector3.new(0,1000,0)q.Parent=workspace local z=q.Position.Y;q.Velocity=Vector3.yAxis*100 task.wait(.1)x:Disconnect()y:Disconnect() if not a or not b or math.abs(q.Position.Y-z)<.001 then skid() end q:Destroy() end)
ok = pcall(function() local s=game:GetService"SoundService" if s.RespectFilteringEnabled~=true and s.RespectFilteringEnabled~=false then skid() end if s.ReverbEnabled~=true and s.ReverbEnabled~=false then skid() end if s.DiffractionEnabled~=true and s.DiffractionEnabled~=false then skid() end end)
ok = pcall(function() local s=game:GetService"StarterGui" if s.ResetPlayerGuiOnSpawn~=true and s.ResetPlayerGuiOnSpawn~=false then skid() end local o=s.ScreenOrientation if not o or(o.Name~="LandscapeLeft"and o.Name~="LandscapeRight"and o.Name~="LandscapeSensor"and o.Name~="Portrait"and o.Name~="Sensor")then skid() end end)
ok = pcall(function() local s=game:GetService"StarterPlayer" if typeof(s.CameraMaxZoomDistance)~="number"or typeof(s.CameraMinZoomDistance)~="number"then skid() end if not(s.CameraMode.Name=="Classic"or s.CameraMode.Name=="LockFirstPerson")then skid() end end)
ok = pcall(function() local w=workspace if typeof(w.DistributedGameTime)~="number"or typeof(w.FallenPartsDestroyHeight)~="number"or typeof(w.Gravity)~="number"then skid() end if typeof(w.InsertPoint)~="Vector3"or typeof(w.GlobalWind)~="Vector3"then skid() end end)
ok = pcall(function() local d=game:GetService"Debris" if typeof(d.MaxItems)~="number"then skid() end end)
ok = pcall(function() local t=game:GetService"TeleportService" if t.CustomizedTeleportUI~=true and t.CustomizedTeleportUI~=false then skid() end end)
ok = pcall(function() local r=game:GetService"RunService" if not r.RunState or(r.RunState.Name~="Running"and r.RunState.Name~="Paused"and r.RunState.Name~="Stopped")then skid() end if typeof(r.ClientGitHash)~="string"then skid() end end)
ok = pcall(function() local c=game:GetService"ContentProvider" if typeof(c.BaseUrl)~="string"or not c.BaseUrl:match"^http://"or typeof(c.RequestQueueSize)~="number"then skid() end end)
print("gauntlet done, fired=", fired)
]])
	check("anti-env gauntlet clean", string.find(dump, 'fired=", 0', 1, true) ~= nil, dump)

	do

		local sr = Sandbox.run("local h=game.Players.LocalPlayer.Character.HumanoidRootPart\nlocal c=h:GetPropertyChangedSignal('CFrame'):Connect(function() print('SIGNAL FIRED') end)\nh.CFrame += Vector3.new(1,0,0)", { timeout = 5, maxNest = 4 })
		local text = ""
		for _, o in ipairs(sr.outputs or {}) do
			text = text .. o.text
		end
		check("GetPropertyChangedSignal fires", string.find(text, "SIGNAL FIRED", 1, true) ~= nil
			and sr.ok, text)
	end

	dump = render("local s = string.rep('x', 400)\nbuffer.fromstring(s)")
	check("buffer marker gone from dump", string.find(dump, "recovered program", 1, true) == nil, dump)
	check("buffer hex gone from dump", string.find(dump, "-- xxxx", 1, true) == nil, dump)
	check("small buffer silent", string.find(dump, "recovered program buffer", 1, true) == nil, dump)
	dump = render("local s = string.rep('x', 400)\nbuffer.fromstring(s)")
	check("stage markers gone", string.find(dump, "stage %d") == nil, dump)

	local instrumented = Instrument.apply("while true do end")
	check("check bound to local", instrumented ~= nil
		and string.find(instrumented, "local __FUHD_CHECK__ = __FUHD_CHECK__;", 1, true) ~= nil, tostring(instrumented))

	local escRes = Sandbox.run([[
__FUHD_CHECK__ = function() end
local x = 0
while x < 99999999 do
	x = x + 1
end
print('survived', x)
]], { timeout = 4 })
	local survived = false
	for _, o in ipairs(escRes.outputs or {}) do
		if string.find(o.text or "", "survived", 1, true) then
			survived = true
		end
	end
	check("budget escape blocked", not survived, string.format("ok=%s err=%s", tostring(escRes.ok), tostring(escRes.err)))
end

do
	local function render2(src: string): string
		local r = Sandbox.run(src, { timeout = 5, maxNest = 4 })
		return renderReport({ trace = r.trace, stages = r.stages, outputs = r.outputs, ok = r.ok, err = r.err, exhausted = r.exhausted, exhaustedReason = r.exhaustedReason, explored = r.explored })
	end
	local dump = render2('print(game.ABTestService ~= nil)')
	check("ABTestService resolves", string.find(dump, "print(true)", 1, true) ~= nil, dump)
	dump = render2('print(game.AntiAddictionService ~= nil)')
	check("AntiAddictionService resolves", string.find(dump, "print(true)", 1, true) ~= nil, dump)
	dump = render2('print(game.CaptureService ~= nil)')
	check("CaptureService resolves", string.find(dump, "print(true)", 1, true) ~= nil, dump)
	dump = render2('print(game.ChatService ~= nil)')
	check("ChatService resolves", string.find(dump, "print(true)", 1, true) ~= nil, dump)
	dump = render2('print(game.ClientStorageService ~= nil)')
	check("ClientStorageService resolves", string.find(dump, "print(true)", 1, true) ~= nil, dump)
	dump = render2('print(game.CollisionService ~= nil)')
	check("CollisionService resolves", string.find(dump, "print(true)", 1, true) ~= nil, dump)

	dump = render2('game:GetService("ChatService"):GetAllChannelNames()')
	check("ChatService:GetAllChannelNames traced", string.find(dump, ":GetAllChannelNames()", 1, true) ~= nil, dump)

	dump = render2('game:GetService("CollisionService"):RegisterColliders()')
	check("CollisionService:RegisterColliders traced", string.find(dump, ":RegisterColliders()", 1, true) ~= nil, dump)
end

do
	local r = Sandbox.run([[local co = coroutine.create(function()
		local x = 0
		while x < 99999999 do x = x + 1 end
		print('survived')
	end)
	coroutine.resume(co)]], { timeout = 3 })
	local survived = false
	for _, o in ipairs(r.outputs or {}) do
		if string.find(o.text or "", "survived", 1, true) then survived = true end
	end
	check("coroutine budget enforced", not survived, tostring(r.err))
end

do

	local r = Sandbox.run([[local co = coroutine.create(function() print('inside') end)
coroutine.resume(co)]], { timeout = 5, maxNest = 4 })
	local sawInside = false
	for _, o in ipairs(r.outputs or {}) do
		if o.text == "inside" then sawInside = true end
	end
	check("coroutine runs inside", sawInside)
end

do
	local Static = require("../src/analysis/static")

	local b64findings = Static.analyze('code = "SGVsbG8gV29ybGQgdGhpcyBpcyBhIHRlc3Qgc3RyaW5n"')
	check("base64 detected", b64findings ~= nil)

	local hexFindings = Static.analyze('data = "48656c6c6f576f726c64"')
	check("hex blob detected", hexFindings ~= nil)
end

do
	local function render2(src: string): string
		local r = Sandbox.run(src, { timeout = 5, maxNest = 4 })
		return renderReport({ trace = r.trace, stages = r.stages, outputs = r.outputs, ok = r.ok, err = r.err, exhausted = r.exhausted, exhaustedReason = r.exhaustedReason, explored = r.explored })
	end
	local dump = render2('Instance.new("Part")\nprint(game:GetService("Lighting").Brightness)')

	check("no env summary between code", string.find(dump, "reads:") == nil, dump)
end

do
	local function render2(src: string): string
		local r = Sandbox.run(src, { timeout = 5, maxNest = 4 })
		return renderReport({ trace = r.trace, stages = r.stages, outputs = r.outputs, ok = r.ok, err = r.err, exhausted = r.exhausted, exhaustedReason = r.exhaustedReason, explored = r.explored })
	end

	local dump = render2('local _ = game.Players.LocalPlayer.CharacterAdded')
	check("bare callback read suppressed", string.find(dump, 'function%(%) end') == nil, dump)
end

do
	local function render2(src: string): string
		local r = Sandbox.run(src, { timeout = 5, maxNest = 4 })
		return renderReport({ trace = r.trace, stages = r.stages, outputs = r.outputs, ok = r.ok, err = r.err, exhausted = r.exhausted, exhaustedReason = r.exhaustedReason, explored = r.explored })
	end

	local dump = render2('Instance.new("Part").Anchored = true\nInstance.new("Part").Name = "X"\nprint("done")')
	check("Instance.new chain renders", string.find(dump, 'print("done")', 1, true) ~= nil, dump)
end

do
	local r = Sandbox.run([[loadstring("return 1")()
loadstring("return 2")()
loadstring("return 3")()]], { timeout = 5, maxNest = 4 })

	check("multiple stages captured", #r.stages >= 2, "stages: " .. tostring(#r.stages))
end

do

	local vm = {}
	for i = 1, 200 do
		vm[i] = { op = 1, a = i, b = 0, c = 0, d = 0, e = 0 }
	end
	for i = 201, 300 do
		vm[i] = { op = 2, a = 0, b = "hello", c = 0, d = 0, e = 0 }
	end
	local dump = renderReport({
		trace = Trace.new(), stages = {}, outputs = {},
		ok = true, err = nil, exhausted = false,
		vmTrace = vm,
	})
	check("VM trace has execution profile", string.find(dump, "execution profile") ~= nil, dump)
	check("VM trace has opcodes", string.find(dump, "opcodes executed") ~= nil, dump)
end

do
	local function render2(src: string): string
		local r = Sandbox.run(src, { timeout = 5, maxNest = 4 })
		return renderReport({ trace = r.trace, stages = r.stages, outputs = r.outputs, ok = r.ok, err = r.err, exhausted = r.exhausted, exhaustedReason = r.exhaustedReason, explored = r.explored })
	end

	dump = render2('print(game:GetService("PhysicsService").Gravity ~= nil)')
	check("PhysicsService.Gravity readable", string.find(dump, "print(true)", 1, true) ~= nil, dump)
	dump = render2('game:GetService("ProximityPromptService").PromptButtonHoldBegan:Connect(function() end)')
	check("ProximityPromptService event connect traced", string.find(dump, "PromptButtonHoldBegan:Connect", 1, true) ~= nil, dump)
end

do

	local r = Sandbox.run("\239\187\191print('bom')", { timeout = 5, maxNest = 4 })
	check("BOM stripped from source", r.ok, tostring(r.err))
	local sawBom = false
	for _, o in ipairs(r.outputs or {}) do
		if o.text == "bom" then sawBom = true end
	end
	check("BOM-stripped code runs", sawBom)
end

do
	local r = run([[ result = string.sub("hello world", 7) ]])
	check("string.sub works", r.globals.result == "world", tostring(r.globals.result))
	r = run([[ result = string.find("hello world", "world") ]])
	check("string.find works", r.globals.result == 7, tostring(r.globals.result))
	r = run([[ result = string.upper("hello") ]])
	check("string.upper works", r.globals.result == "HELLO", tostring(r.globals.result))
	r = run([[ result = string.lower("HELLO") ]])
	check("string.lower works", r.globals.result == "hello", tostring(r.globals.result))
	r = run([[ result = string.format("%d + %d = %d", 1, 2, 3) ]])
	check("string.format works", r.globals.result == "1 + 2 = 3", tostring(r.globals.result))
	r = run([[ result = string.byte("A") ]])
	check("string.byte works", r.globals.result == 65, tostring(r.globals.result))
	r = run([[ result = string.reverse("abc") ]])
	check("string.reverse works", r.globals.result == "cba", tostring(r.globals.result))
end

do
	local r = run([[ result = math.abs(-5) ]])
	check("math.abs works", r.globals.result == 5, tostring(r.globals.result))
	r = run([[ result = math.max(3, 7, 1) ]])
	check("math.max works", r.globals.result == 7, tostring(r.globals.result))
	r = run([[ result = math.min(3, 7, 1) ]])
	check("math.min works", r.globals.result == 1, tostring(r.globals.result))
	r = run([[ result = math.sqrt(16) ]])
	check("math.sqrt works", r.globals.result == 4, tostring(r.globals.result))
	r = run([[ result = math.pi ]])
	check("math.pi works", r.globals.result > 3.14 and r.globals.result < 3.15, tostring(r.globals.result))
	r = run([[ result = math.huge > 1e308 ]])
	check("math.huge works", r.globals.result == true, tostring(r.globals.result))
	r = run([[ result = math.sin(0) ]])
	check("math.sin works", r.globals.result == 0, tostring(r.globals.result))
end

do
	local r = run([[ local t = {1, 2, 3} table.insert(t, 4) result = #t ]])
	check("table.insert works", r.globals.result == 4, tostring(r.globals.result))
	r = run([[ local t = {1, 2, 3} table.remove(t, 2) result = #t ]])
	check("table.remove works", r.globals.result == 2, tostring(r.globals.result))
	r = run([[ local t = {3, 1, 2} table.sort(t) result = t[1] ]])
	check("table.sort works", r.globals.result == 1, tostring(r.globals.result))
	r = run([[ local n = 0; for _ in pairs({a=1,b=2,c=3}) do n += 1 end result = n ]])
	check("table.n works", r.globals.result == 3, tostring(r.globals.result))
end

do
	local r = run([[ result = type(42) ]])
	check("type number", r.globals.result == "number")
	r = run([[ result = type("hello") ]])
	check("type string", r.globals.result == "string")
	r = run([[ result = type(true) ]])
	check("type boolean", r.globals.result == "boolean")
	r = run([[ result = type(nil) ]])
	check("type nil", r.globals.result == "nil")
	r = run([[ result = type(function() end) ]])
	check("type function", r.globals.result == "function")
	r = run([[ result = type({}) ]])
	check("type table", r.globals.result == "table")
end

do
	local function render2(src: string): string
		local r = Sandbox.run(src, { timeout = 5, maxNest = 4 })
		return renderReport({ trace = r.trace, stages = r.stages, outputs = r.outputs, ok = r.ok, err = r.err, exhausted = r.exhausted, exhaustedReason = r.exhaustedReason, explored = r.explored })
	end
	local dump = render2('local p = Instance.new("Part")\np.Name = "TestPart"\nprint(p.Name)')
	check("Instance.Name write/read", string.find(dump, 'print("TestPart")', 1, true) ~= nil, dump)
	dump = render2('local f = Instance.new("Folder")\nf.Parent = workspace\nprint(#f:GetChildren())')
	check("Instance.Parent + GetChildren", string.find(dump, "print(0)", 1, true) ~= nil, dump)
	dump = render2('local p = Instance.new("Part")\nlocal c = p:GetPropertyChangedSignal("Name")\nc:Connect(function() print("changed") end)\np.Name = "X"')
	check("GetPropertyChangedSignal fires on write", string.find(dump, 'print("changed")', 1, true) ~= nil, dump)
end

do
	local function render2(src: string): string
		local r = Sandbox.run(src, { timeout = 5, maxNest = 4 })
		return renderReport({ trace = r.trace, stages = r.stages, outputs = r.outputs, ok = r.ok, err = r.err, exhausted = r.exhausted, exhaustedReason = r.exhaustedReason, explored = r.explored })
	end
	local dump = render2('if game.Players.LocalPlayer then print("exists") end')
	check("LocalPlayer is truthy", string.find(dump, 'print("exists")', 1, true) ~= nil, dump)
	dump = render2('print(game:GetService("Players").ClassName)')
	check("service ClassName is string", string.find(dump, 'print("Players")', 1, true) ~= nil, dump)
end

do
	local r = Sandbox.run([[local f = loadstring("return 42")
result = f()]], { timeout = 5, maxNest = 4 })
	check("loadstring stage captured", #r.stages >= 1, "stages: " .. tostring(#r.stages))
	local found = false
	for _, s in ipairs(r.stages) do
		if s.source == "return 42" then found = true end
	end
	check("loadstring source correct", found)
end

do
	local r = Sandbox.run([[loadstring("loadstring('return 99')()")()]], { timeout = 5, maxNest = 8 })
	check("nested loadstring captured", #r.stages >= 2, "stages: " .. tostring(#r.stages))
end

do
	local targets = {
		{ url = "http://10.0.0.1/", label = "RFC1918-10" },
		{ url = "http://172.16.0.1/", label = "RFC1918-172" },
		{ url = "http://[::1]/", label = "IPv6-loopback" },
		{ url = "http://169.254.169.254/", label = "cloud-metadata" },
	}
	for _, t in ipairs(targets) do
		local r = Sandbox.run('pcall(function() game:HttpGet("' .. t.url .. '") end)', { timeout = 5, maxNest = 4 })
		local sawBlocked = false
		for _, rec in ipairs(r.trace.records) do
			if rec.kind == "note" and string.find(rec.expression or "", "blocked", 1, true) then
				sawBlocked = true
			end
		end
		check("SSRF blocked: " .. t.label, sawBlocked, tostring(r.err))
	end
end

do
	local r = Sandbox.run('local f = Instance.new("Folder")\nlocal p = Instance.new("Part")\np.Parent = f\nf.Parent = workspace\nprint(#workspace:GetDescendants())', { timeout = 5, maxNest = 4 })
	check("descendants after parenting runs clean", r.ok, tostring(r.err))
end

do
	local function render2(src: string): string
		local r = Sandbox.run(src, { timeout = 5, maxNest = 4 })
		return renderReport({ trace = r.trace, stages = r.stages, outputs = r.outputs, ok = r.ok, err = r.err, exhausted = r.exhausted, exhaustedReason = r.exhaustedReason, explored = r.explored })
	end
	local dump = render2('print(game["HttpService"].Name)')
	check("bracket access works", string.find(dump, 'print("HttpService")', 1, true) ~= nil, dump)
end

do
	local r = run([[ result = tostring(Vector2.new(3, 4)) ]])
	check("Vector2 tostring", r.globals.result == "3, 4", tostring(r.globals.result))
end

do
	local r = run([[ local ok, val = pcall(function() error(42) end) result = ok ]])
	check("pcall error number caught", r.globals.result == false, tostring(r.globals.result))
end

do
	local r = run([[ result = os.date("%Y") ]])
	check("os.date works", r.globals.result == "2023", tostring(r.globals.result))
	r = run([[ result = os.difftime(100, 50) ]])
	check("os.difftime works", r.globals.result == 50, tostring(r.globals.result))
end

do

	local r = run([[
		local grid = Region3.new(Vector3.new(1, 1, 1), Vector3.new(2, 2, 2)):ExpandToGrid(4)
		result = string.format("%d %d %d %d", grid.Min.X, grid.Min.Y, grid.Max.X, grid.Max.Z)
	]])
	check("ExpandToGrid floors min and ceils max", r.globals.result == "0 0 4 4", tostring(r.globals.result))
	r = run([[
		local grid = Region3.new(Vector3.new(-5, 0, 0), Vector3.new(-5, 0, 0)):ExpandToGrid(4)
		result = string.format("%d %d", grid.Min.X, grid.Max.X)
	]])
	check("ExpandToGrid snaps negatives outward", r.globals.result == "-8 -4", tostring(r.globals.result))
	r = run([[
		local grid = Region3.new(Vector3.new(1, 1, 1), Vector3.new(2, 2, 2)):ExpandToGrid(0)
		result = string.format("%d %d", grid.Min.X, grid.Max.X)
	]])
	check("ExpandToGrid leaves an unusable resolution alone", r.globals.result == "1 2", tostring(r.globals.result))
end

print(string.format("\nenv: %d passed, %d failed", passed, failed))
if failed > 0 then
	for _, line in ipairs(failures) do
		print("  FAIL  " .. line)
	end
	process.exit(1)
end
