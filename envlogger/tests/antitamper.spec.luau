local fs = require("@lune/fs")
local process = require("@lune/process")
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
	local result = Sandbox.run(source, { timeout = timeout or 90, maxExplored = 0 })
	local lines: { string } = {}
	for _, entry in ipairs(result.outputs or {}) do
		lines[#lines + 1] = string.gsub(tostring(entry.text), "\t", " ")
	end
	return lines, result
end

local function fixture(name: string): string
	return fs.readFile("tests/antitamper/" .. name)
end

do
	local lines, result = outputsOf(fixture("at1_sharedtable.lua"), 40)
	check("at1 ran", result.ok, tostring(result.err))
	check("at1 verdict", lines[1] == "ud", table.concat(lines, " | "))

	local deep = outputsOf([[
		local a = SharedTable.new()
		local b = SharedTable.new()
		a.x = b
		b.y = 7
		local c = SharedTable.cloneAndFreeze(a, true)
		b.y = 9
		print("snapshot", c.x.y)
		print("frozen", not pcall(function() c.x.y = 1 end))
	]], 20)
	check("at1 deep clone snapshots", deep[1] == "snapshot 7", tostring(deep[1]))
	check("at1 deep clone freezes children", deep[2] == "frozen true", tostring(deep[2]))

	local shallow = outputsOf([[
		local a = SharedTable.new()
		local b = SharedTable.new()
		a.x = b
		b.y = 7
		local c = SharedTable.cloneAndFreeze(a, false)
		b.y = 9
		print("aliased", c.x.y)
		print("top frozen", not pcall(function() c.x = 1 end))
	]], 20)
	check("at1 shallow clone aliases", shallow[1] == "aliased 9", tostring(shallow[1]))
	check("at1 shallow clone freezes top", shallow[2] == "top frozen true", tostring(shallow[2]))

	local statics = outputsOf([[
		local a = SharedTable.new({ n = 1 })
		print("size", SharedTable.size(a))
		print("isFrozen", SharedTable.isFrozen(a))
		print("inc", SharedTable.increment(a, "n", 5), a.n)
		print("typeof", typeof(a))
		print("no Get method", a.Get == nil)
		print("plain table refused", not pcall(function() a.t = {} end))
	]], 20)
	check("at1 size", statics[1] == "size 1", tostring(statics[1]))
	check("at1 isFrozen", statics[2] == "isFrozen false", tostring(statics[2]))
	check("at1 increment returns old value", statics[3] == "inc 1 6", tostring(statics[3]))
	check("at1 typeof", statics[4] == "typeof SharedTable", tostring(statics[4]))
	check("at1 no Get method", statics[5] == "no Get method true", tostring(statics[5]))
	check("at1 plain table refused", statics[6] == "plain table refused true", tostring(statics[6]))
end

do
	local lines, result = outputsOf(fixture("at2_surface.lua"), 60)
	check("at2 ran", result.ok, tostring(result.err))

	check("at2 verdict", lines[1] == "pass", table.concat(lines, " | "))
end

do
	local source = fixture("at3_errors.lua")
	local lines, result = outputsOf(source, 40)
	check("at3 ran", result.ok, tostring(result.err))

	local raised: { [string]: boolean } = {}
	for _, line in ipairs(lines) do
		local id = string.match(line, "^ud (%d+)$")
		if id then
			raised[id] = true
		end
	end
	local expectedIds = { 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
	local missing: { string } = {}
	for _, id in ipairs(expectedIds) do
		if not raised[tostring(id)] then
			missing[#missing + 1] = tostring(id)
		end
	end
	check("at3 every check raised", #missing == 0, "missing " .. table.concat(missing, ", "))
	check("at3 no extra output", #lines == #expectedIds, table.concat(lines, " | "))

	local strict = string.gsub(
		source,
		'	else\n		print%("ud", id%)\n	end',
		'	else\n		print("WRONG", id, err)\n	end',
		1
	)
	check("at3 strict patch applied", strict ~= source)
	local strictLines = outputsOf(strict, 40)
	local wrong: { string } = {}
	for _, line in ipairs(strictLines) do
		if string.match(line, "^WRONG ") then
			wrong[#wrong + 1] = line
		end
	end

	check("at3 only id 6 diverges", #wrong == 1, table.concat(wrong, " | "))
	check(
		"at3 id 6 diverges for the documented reason",
		#wrong == 1 and string.find(wrong[1], "^WRONG 6 ") ~= nil
			and string.find(wrong[1], "attempt to index nil with 'new'", 1, true) ~= nil,
		table.concat(wrong, " | ")
	)
end

do

	local source = fixture("at4_obscura.lua") .. fixture("at4_driver.src.txt")
	local lines, result = outputsOf(source, 90)
	check("at4 ran", result.ok, tostring(result.err))
	check("at4 reached the end", lines[#lines] == "done", tostring(lines[#lines]))

	local KNOWN_BROKEN: { [string]: boolean } = {
		["FIRED validateTraceback x1"] = true,
		["FIRED verifyDebugTraceback x1"] = true,
	}
	local seen: { [string]: boolean } = {}
	local bad: { string } = {}
	local oks, brokenCount = 0, 0
	for _, line in ipairs(lines) do
		seen[line] = true
		if KNOWN_BROKEN[line] then
			brokenCount += 1
		elseif string.match(line, "^ok ") then
			oks += 1
		elseif line ~= "done" then
			bad[#bad + 1] = line
		end
	end

	check("at4 nothing raised or fired", #bad == 0, table.concat(bad, " | "))
	check("at4 ran the whole battery", oks >= 50, tostring(oks) .. " ok lines")
	check("at4 both fixture bugs still present", brokenCount == 2, tostring(brokenCount))

	check("at4 validateTraceback quiet once repaired", seen["ok validateTraceback (bug repaired)"] == true)
	check("at4 verifyDebugTraceback quiet once repaired", seen["ok verifyDebugTraceback (bug repaired)"] == true)
end

print(string.format("\nantitamper: %d passed, %d failed", passed, failed))
if failed > 0 then
	for _, line in ipairs(failures) do
		print("  FAIL  " .. line)
	end
	process.exit(1)
end
