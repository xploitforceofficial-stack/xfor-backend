local fs = require("@lune/fs")
local process = require("@lune/process")
local Sandbox = require("../src/core/sandbox")
local Report = require("../src/analysis/report")
local Sanitize = require("../src/core/sanitize")

local ENGINE_LEAKS = {
	"/Users/",
	"\\Users\\",
	"C:\\",
	"/home/",
	"/app/",
	"envlogger/src",
	"envlogger\\src",
	"src/core/",
	"src/env/",
	"src/analysis/",
	"src/main",
	".luau:%d+: in ",
	"stack traceback:%s*\n%s*%S-[/%\\]",
	"/tmp/omnidbf",
}

local function engineLeaks(text: string): { string }
	local found = {}
	for _, pat in ipairs(ENGINE_LEAKS) do
		if string.find(text, pat, 1, false) ~= nil then
			found[#found + 1] = pat
		end
	end
	return found
end

local cases = {
	{ name = "plain error", src = 'error("boom")' },
	{ name = "nil call crash", src = "local t = nil; t.foo()" },
	{ name = "syntax error", src = "local x = {" },
	{ name = "loadstring of bad code", src = "loadstring('this is not lua')()" },
	{ name = "error inside nested loadstring", src = 'loadstring("error(42, 0)")()' },
	{ name = "stack overflow", src = "local function f() return 1 + f() end f()" },
	{ name = "debug.traceback probe", src = "print(debug.traceback()) local e = getfenv().debug print(e.traceback())" },
	{ name = "error with object message", src = 'error(setmetatable({}, {__tostring = function() return "custom" end}))' },
	{ name = "long error string", src = "error(string.rep('x', 5000))" },
}

local failures = 0
local function scanRun(caseName: string, res: any)
	local surfaces = {}

	local okR, rendered = pcall(Report.render, {
		trace = res.trace,
		stages = res.stages,
		outputs = res.outputs,
		ok = res.ok,
		err = res.err,
		exhausted = res.exhausted,
		exhaustedReason = res.exhaustedReason,
		elapsed = 0,
		inputBytes = #caseName,
	}, { maxStatements = 5000 })
	if okR and type(rendered) == "string" then
		surfaces["report"] = rendered
	else
		surfaces["report-fallback"] = Sanitize.message(tostring(rendered))
	end

	surfaces["err"] = res.err or ""
	local notes = ""
	for _, r in ipairs(res.trace.records) do
		if r.kind == "note" and type(r.expression) == "string" then
			notes ..= r.expression .. "\n"
		end
	end
	surfaces["notes"] = notes

	for surface, text in surfaces do
		local bad = engineLeaks(text)
		if #bad > 0 then
			failures += 1
			print(("FAIL [%s/%s] leaks: %s"):format(caseName, surface, table.concat(bad, ", ")))
			local snippet = string.sub(text, 1, 300)
			print("  text: " .. (snippet:gsub("[\n\r]", " | ")))
		end
	end
end

for _, case in ipairs(cases) do
	local ok, res = pcall(Sandbox.run, case.src, { timeout = 10, maxNest = 2 })
	if ok then
		scanRun(case.name, res)
	else
		local msg = Sanitize.message(tostring(res))
		local bad = engineLeaks(msg)
		if #bad > 0 then
			failures += 1
			print(("FAIL [%s] escaped error leaks: %s"):format(case.name, table.concat(bad, ", ")))
			print("  text: " .. (msg:gsub("[\n\r]", " | ")))
		end
	end
end

if failures > 0 then
	print(("\n%d LEAK(S) FOUND"):format(failures))
	process.exit(1)
end
print("\nALL CLEAN - no engine paths, line frames or internals in user-visible output")
