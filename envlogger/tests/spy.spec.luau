local luau = require("@lune/luau")
local process = require("@lune/process")
local Spy = require("../src/core/spy")
local Trace = require("../src/core/trace")

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

local function runInSandbox(src: string, seeds: { [string]: any }?)
	local trace = Trace.new()
	local config = { trace = trace, nest = 0 }
	local roots: { [string]: any } = {}

	local env = setmetatable({}, {
		__index = function(_, key)
			if seeds and seeds[key] ~= nil then
				return seeds[key]
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
			roots[key] = value
		end,
	})

	local fn = luau.load(src, { environment = env, injectGlobals = false })
	local ok, err = pcall(fn)
	return trace, ok, err
end

local function expressions(trace)
	local out = {}
	for _, record in ipairs(trace.records) do
		out[#out + 1] = record.expression
	end
	return out
end

local function traceHas(trace, needle: string): boolean
	for _, record in ipairs(trace.records) do
		if string.find(record.expression, needle, 1, true) then
			return true
		end
	end
	return false
end

do
	local trace, ok = runInSandbox([[ local x = game.Players.LocalPlayer.Character ]])
	check("chain runs", ok)
	check("chain records full path", traceHas(trace, "game.Players.LocalPlayer.Character"),
		table.concat(expressions(trace), " | "))
end

do
	local trace, ok = runInSandbox([[ local s = game:GetService("Players") ]])
	check("service call runs", ok)
	check("service call recorded", traceHas(trace, 'GetService("Players")'),
		table.concat(expressions(trace), " | "))
end

do
	local trace, ok = runInSandbox([[ remote:FireServer("a", 1, true) ]])
	check("namecall runs", ok)
	check("namecall args recorded", traceHas(trace, '"a", 1, true'),
		table.concat(expressions(trace), " | "))

	local hasSelfLeak = traceHas(trace, "remote.FireServer(remote")
	check("namecall renders as method (no self leak)", not hasSelfLeak,
		table.concat(expressions(trace), " | "))
end

do
	local hostileOps = {
		["arithmetic on unknown"] = [[ local x = unknown + 1 ]],
		["concat unknown"] = [[ local x = unknown .. "tail" ]],
		["length of unknown"] = [[ local x = #unknown ]],
		["negate unknown"] = [[ local x = -unknown ]],
		["call unknown"] = [[ unknown() ]],
		["deep index"] = [[ local x = a.b.c.d.e.f.g.h ]],
		["iterate unknown"] = [[ for k, v in pairs(unknown) do end ]],
		["index with nil-ish"] = [[ local x = unknown[unknown] ]],
		["assign to unknown field"] = [[ unknown.field = 42 ]],
		["tostring unknown"] = [[ local x = tostring(unknown) ]],
		["modulo chain"] = [[ local x = (unknown * 7 + 3) % 256 ]],
		["nested call"] = [[ unknown(unknown(unknown)) ]],
		["method on unknown"] = [[ unknown:Method() ]],
		["compare two unknowns"] = [[ local x = a == b ]],
		["numeric for with unknown"] = [[ for i = 1, 3 do local y = unknown + i end ]],
	}
	for name, src in pairs(hostileOps) do
		local _, ok, err = runInSandbox(src)
		check("survives: " .. name, ok, tostring(err))
	end
end

do

	local trace = Trace.new()
	local config = {
		trace = trace,
		nest = 0,
		onIndex = function(_, key)
			if key == "Health" then
				return true, 87.5
			elseif key == "Name" then
				return true, "Humanoid"
			end
			return false, nil
		end,
	}
	local root = Spy.root("character", config)

	check("scalar field is raw number", root.Health == 87.5, tostring(root.Health))
	check("scalar compares natively", (root.Health < 100) == true)
	check("scalar arithmetic", (root.Health * 2) == 175)
	check("string field is raw", root.Name == "Humanoid")
	check("string method works", root.Name:upper() == "HUMANOID")
	check("tonumber works", tonumber(root.Health) == 87.5)
end

do

	local trace = Trace.new()
	local config = { trace = trace, nest = 0 }
	local backing = { count = 3, label = "abc", nested = { deep = 9 } }
	local root = Spy.new("cfg", config, backing, true)

	check("table-backed scalar", root.count == 3, tostring(root.count))
	check("table-backed compare", (root.count >= 3) == true)
	check("table-backed string", root.label == "abc")
	check("nested table stays proxy", Spy.is(root.nested))
	check("nested scalar unwraps", root.nested.deep == 9, tostring(root.nested.deep))
end

do
	local trace = Trace.new()
	local config = { trace = trace, nest = 0 }

	check("unknown treated as 0 in add", (Spy.new("u", config) + 5) == 5)
	check("unknown treated as 0 in mul", (Spy.new("u", config) * 5) == 0)
	check("unknown concat uses path", (Spy.new("u", config) .. "!") == "u!")
	check("unknown tostring uses path", tostring(Spy.new("u", config)) == "u")
	check("unknown len is 0", #Spy.new("u", config) == 0)
end

do
	local trace = Trace.new()
	local config = { trace = trace, nest = 0 }
	local root = Spy.root("game", config)
	check("repeat index same identity", root.Players == root.Players)
	check("distinct fields differ", root.Players ~= root.Lighting)
end

do
	local trace = Trace.new()
	local config = { trace = trace, nest = 0 }
	local root = Spy.root("obj", config)
	root.marker = "written"
	check("read back written field", root.marker == "written", tostring(root.marker))
end

do
	local trace = Trace.new()
	local config = { trace = trace, nest = 0 }
	local root = Spy.root("game", config)
	check("metatable hidden", getmetatable(root) == "The metatable is locked", tostring(getmetatable(root)))
	local ok = pcall(setmetatable, root, {})
	check("setmetatable blocked", not ok)
end

do

	local cases = {
		["spied pairs over unknown"] = [[ for k, v in pairs(unknown) do end ]],
		["spied ipairs over unknown"] = [[ for i, v in ipairs(unknown) do end ]],
		["spied pairs over field"] = [[ for k, v in pairs(game.Players) do end ]],
		["direct for over spy"] = [[ for k, v in unknown do end ]],
	}
	for name, src in pairs(cases) do
		local _, ok, err = runInSandbox(src)
		check("iterates: " .. name, ok, tostring(err))
	end
end

do

	local spyAwareNext = function(subject: any, control: any)
		if type(subject) == "userdata" then
			return nil
		end
		return next(subject, control)
	end
	local realIterators = { next = spyAwareNext, pairs = pairs, ipairs = ipairs }

	local _, okUnknown, errUnknown =
		runInSandbox([[ for k, v in next, unknown do end ]], realIterators)
	check("real next over spied value", okUnknown, tostring(errUnknown))

	local seen = 0
	local _, okReal, errReal = runInSandbox(
		[[ for k, v in next, realTable do count() end ]],
		{
			next = spyAwareNext,
			realTable = { a = 1, b = 2 },
			count = function()
				seen += 1
			end,
		}
	)
	check("real next over real table", okReal, tostring(errReal))
	check("real next visited entries", seen == 2, tostring(seen))
end

do

	local visited = {}
	local _, ok, err = runInSandbox(
		[[ for k, v in pairs(realTable) do record(k) end ]],
		{
			realTable = { alpha = 1, beta = 2, gamma = 3 },
			record = function(k)
				visited[#visited + 1] = k
			end,
		}
	)
	check("spied pairs visits real entries", ok, tostring(err))
	check("visited all three keys", #visited == 3, tostring(#visited))
end

do
	local trace, ok = runInSandbox([[ local h = game:GetService("HttpService") ]])
	check("method form rendered", traceHas(trace, 'game:GetService("HttpService")'),
		table.concat(expressions(trace), " | "))
	check("method run ok", ok)

	local kinds = {}
	for _, record in ipairs(trace.records) do
		kinds[record.kind] = true
	end
	check("namecall kind recorded", kinds.namecall == true)
end

do

	local trace = runInSandbox([[ local x = lib.helper(1, 2) ]])
	check("dot call keeps dot", traceHas(trace, "lib.helper(1, 2)"),
		table.concat(expressions(trace), " | "))
end

do
	local trace = Trace.new()
	local config = { trace = trace, nest = 0 }
	local withValue = Spy.new("n", config, 99, true)
	check("unwrap concrete", Spy.unwrap(withValue) == 99)
	check("unwrap unknown -> nil", Spy.unwrap(Spy.new("u", config)) == nil)
	check("unwrap plain passthrough", Spy.unwrap(5) == 5)

	local mixed = { a = withValue, b = 7 }
	local flat = Spy.unwrap(mixed)
	check("unwrap table", flat.a == 99 and flat.b == 7)

	local noProxies = { x = 1 }
	check("unwrap avoids copy when clean", Spy.unwrap(noProxies) == noProxies)

	local cyclic = {}
	cyclic.self = cyclic
	cyclic.spy = withValue
	local okCycle = pcall(Spy.unwrap, cyclic)
	check("unwrap survives cycle", okCycle)
end

do
	local trace = Trace.new(5)
	for i = 1, 20 do
		trace:push("note", "n" .. i, 0)
	end
	check("trace limit enforced", #trace.records == 5, tostring(#trace.records))
	check("trace counts dropped", trace.dropped == 15, tostring(trace.dropped))
	check("trace total count", trace.count == 20)
end

do
	local trace = Trace.new()
	trace:push("note", "keep", 0)
	local mark = trace:push("note", "drop", 0)
	trace:push("note", "drop2", 0)
	trace:truncate(mark)
	check("truncate removes tail", #trace.records == 1, tostring(#trace.records))
	check("truncate resets count", trace.count == mark - 1, tostring(trace.count))
end

do
	local trace = Trace.new()
	trace:push("call", "a()", 0)
	trace:push("index", "b.c", 0)
	trace:push("call", "d()", 0)
	check("ofKind filters", #trace:ofKind("call") == 2)
end

print(string.format("\nspy: %d passed, %d failed", passed, failed))
if failed > 0 then
	for _, line in ipairs(failures) do
		print("  FAIL  " .. line)
	end
	process.exit(1)
end
