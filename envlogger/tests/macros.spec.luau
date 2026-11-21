local Sandbox = require("../src/core/sandbox")
local Report = require("../src/analysis/report")

local passes, fails = 0, 0
local function check(name: string, cond: boolean, detail: string?)
	if cond then
		passes += 1
	else
		fails += 1
		print("[FAIL] " .. name .. " :: " .. tostring(detail))
	end
end

local function runWithMacros(source: string, macros: { [string]: any }?)
	local r = Sandbox.run(source, {
		timeout = 15,
		maxExplored = 0,
		macros = macros,
	})
	return r, Report.render({
		trace = r.trace,
		stages = r.stages,
		outputs = r.outputs,
		ok = r.ok,
		err = r.err,
		exhausted = r.exhausted,
	}, {})
end

local r, dump = runWithMacros("print(game.PlaceId)\nprint(game.JobId)", {
	PlaceId = 253214217,
	JobId = 999,
})
check("game.PlaceId macro", string.find(dump, "print(253214217)", 1, true) ~= nil, dump)
check("game.JobId macro", string.find(dump, "print(999)", 1, true) ~= nil, dump)

r, dump = runWithMacros('local p = Instance.new("Part")\nprint(p.PlaceId)', { PlaceId = 123 })
check("part.PlaceId macro", string.find(dump, "print(123)", 1, true) ~= nil, dump)

r, dump = runWithMacros('print(game:GetService("Players").LocalPlayer.Name)', { Name = "Player1337" })
check("LocalPlayer.Name macro", string.find(dump, 'print("Player1337")', 1, true) ~= nil, dump)

r, dump = runWithMacros('preindex({ SecretKey = "shh" })\nprint(game.SecretKey)\nprint(workspace.SecretKey)', nil)
check("preindex in-script game", string.find(dump, 'print("shh")', 1, true) ~= nil, dump)

r, dump = runWithMacros("print(Instance.new('Part').Parent)", { Parent = 42 })
check("Parent not overridable to junk", string.find(dump, "nil", 1, true) ~= nil, dump)

r, dump = runWithMacros("print(game.PlaceId > 0)", nil)
check("no-macro default intact", string.find(dump, "true", 1, true) ~= nil, dump)

print(string.format("\nmacros: %d passed, %d failed", passes, fails))
if fails > 0 then
	error("macros spec failed")
end
