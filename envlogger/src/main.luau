local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Beautifier = require("./analysis/beautifier")
local Detector = require("./analysis/detector")
local Report = require("./analysis/report")
local Blocklist = require("./env/blocklist")
local Sandbox = require("./core/sandbox")
local Sanitize = require("./core/sanitize")
local Version = require("./version")

local function parseArguments(args: { string })
	local positional: { string } = {}
	local flags: { [string]: string } = {}

	local index = 1
	while index <= #args do
		local item = args[index]
		if item == "--" then

			index += 1
		elseif string.sub(item, 1, 2) == "--" then
			local name = string.sub(item, 3)
			local value = args[index + 1]
			if value ~= nil and string.sub(value, 1, 2) ~= "--" then
				flags[name] = value
				index += 2
			else
				flags[name] = "true"
				index += 1
			end
		else
			positional[#positional + 1] = item
			index += 1
		end
	end

	return positional, flags
end

local positional, flags = parseArguments(process.args)
local command = positional[1]
local inputPath = positional[2]

local function note(message: string)
	pcall(function()
		local w = (process :: any).stderr
		if type(w) == "table" and type(w.write) == "function" then
			w:write(tostring(message) .. "\n")
		end
	end)
end

local function fail(message: string): never
    message = Sanitize.message(message)
    message = message:gsub("[%w%./\_-]+:%d+:%s*", "")

    print(Report.HEADER)
    note(message)
    process.exit(1)
end

if not command then
	fail("no command given; expected env, detect, const, log, bt or luraph")
end
if not inputPath then
	fail("no input file given")
end

local readOk, source = pcall(fs.readFile, inputPath)
if not readOk or type(source) ~= "string" then
	fail("could not read input file: " .. tostring(inputPath))
end

if string.sub(source, 1, 3) == "\239\187\191" then
	source = string.sub(source, 4)
end

local function deliver(text: string, path: string?)
	if path then
		local ok, err = pcall(fs.writeFile, path, text)
		if not ok then
			fail("could not write output: " .. tostring(err))
		end
	else
		print(text)
	end
end

if command == "detect" then
	local detection = Detector.detect(source)

	if flags.json then
		local payload = {
			name = detection.name,
			confidence = detection.confidence,
			score = detection.score,
			strategy = detection.strategy,
			version = detection.version,
			evidence = detection.evidence,
			metrics = detection.metrics,
			candidates = detection.candidates,
		}
		deliver(serde.encode("json", Sanitize.jsonSafe(payload), true), flags.json)
	else
		local lines = {
			Report.HEADER,
			"",
			string.format("-- obfuscator: %s%s", detection.name, if detection.version then " v" .. detection.version else ""),
			string.format("-- confidence: %s (score %d)", detection.confidence, detection.score),
			string.format("-- strategy:   %s", detection.strategy),
			string.format(
				"-- shape:      %d bytes, %d lines, longest line %d",
				detection.metrics.bytes,
				detection.metrics.lines,
				detection.metrics.longestLine
			),
		}
		if #detection.evidence > 0 then
			lines[#lines + 1] = "-- evidence:"
			for _, item in ipairs(detection.evidence) do
				lines[#lines + 1] = "--   " .. item
			end
		end
		if #detection.candidates > 1 then
			lines[#lines + 1] = "-- other candidates:"
			for index, candidate in ipairs(detection.candidates) do
				if index > 1 then
					lines[#lines + 1] = string.format("--   %s (score %d)", candidate.name, candidate.score)
				end
			end
		end
		deliver(table.concat(lines, "\n"), flags.out)
	end
	return
end

if command == "bt" or command == "beautify" then
	local beautified = Beautifier.format(source)
	deliver(beautified, flags.out)
	return
end

local zlib: any = nil
do
	local ok, loaded = pcall(function()
		return require("../zlib")
	end)
	if ok then
		zlib = loaded
	end
end

local traceLimit = tonumber(flags.tracelimit) or math.min(1000000, 200000 + #source * 2)
local maxStatements = tonumber(flags.maxstatements) or math.min(60000, 20000 + #source // 10)

local started = os.clock()

if command == "luraph" then
	local LuraphExtract = require("./core/luraph_extract")
	local Constants = require("./analysis/constants")

	local detection: any = nil
	do
		local ok, res = pcall(Detector.detect, source)
		if ok then
			detection = res
		end
	end

	local isLuraph = LuraphExtract.isLuraphSource(source)
		or (detection ~= nil and detection.name == "Luraph")
	if not isLuraph and flags.force ~= "true" then
		local name = if detection then detection.name else "unknown"
		fail("this file does not look like Luraph (detected: " .. tostring(name) .. "). Use /dump or /condumper instead.")
	end

	local sandboxResult: any = nil
	local sandboxError: string? = nil

	local stagePatch: { [number]: string }? = nil
	local manifestPath = flags["stage-patch"]
	if manifestPath then
		local okRead, manifest = pcall(fs.readFile, manifestPath)
		if not okRead or type(manifest) ~= "string" then
			fail("could not read the stage-patch manifest at " .. tostring(manifestPath))
		end
		stagePatch = {}
		for line in string.gmatch(manifest, "[^\r\n]+") do
			local len, path = string.match(line, "^(%d+)\t(.+)$")
			if len and path then
				local okStage, text = pcall(fs.readFile, path)
				if okStage and type(text) == "string" then
					stagePatch[tonumber(len)] = text
				else
					fail("could not read the patched stage at " .. path)
				end
			end
		end
		if not next(stagePatch) then
			fail("the stage-patch manifest had no LENGTH<TAB>PATH lines")
		end

		if select(2, next(stagePatch)) == nil then
			local only = next(stagePatch)
			stagePatch[-1] = only
		end
	end

	do
		local okSandbox, resSandbox = pcall(function()
			return Sandbox.run(source, {
				timeout = tonumber(flags.timeout) or 300,
				maxNest = tonumber(flags.maxnest) or 4,
				programDir = flags["dump-program"],
				traceLimit = math.min(traceLimit, 200000),
				onProgress = function() end,
				zlib = zlib,
				httpCache = flags.cache or "cache",
				allowHttp = false,
				scriptKey = flags.scriptkey,
				maxExplored = 0,
				noInstrument = flags.noinstrument == "true",
				noVmPatch = flags.novmpatch == "true",
				stagePatch = stagePatch,

				softInstanceCall = flags.softinstance ~= "false",
				nosoft = flags.nosoft == "true",
			})
		end)
		if okSandbox then
			sandboxResult = resSandbox
		else
			sandboxError = Sanitize.message(tostring(resSandbox))
		end
	end

	local report: any = nil
	do
		local okReport, resReport = pcall(Constants.analyze, source, sandboxResult)
		if okReport then
			report = resReport
		end
	end

	local renderedLines: { string } = { Report.HEADER, "" }

	if sandboxResult and type(sandboxResult.stages) == "table" then
		for _, stage in ipairs(sandboxResult.stages) do
			if type(stage) == "table" and type(stage.source) == "string" and #stage.source > 0 then
				renderedLines[#renderedLines + 1] = stage.source
				renderedLines[#renderedLines + 1] = ""
			end
		end
	end

	if flags.notes == "true" and sandboxResult and type(sandboxResult.vmTrace) == "table" then
		local vm = sandboxResult.vmTrace

		local named = 0
		for _, entry in ipairs(vm) do
			if entry.op ~= nil and entry.op ~= "?" then
				named += 1
			end
		end
		if named == 0 then
			renderedLines[#renderedLines + 1] = "-- vm trace: "
				.. tostring(#vm)
				.. " operations recorded, none with decoded operands (this VM does not use the traced calling convention)"
			renderedLines[#renderedLines + 1] = ""
		else
		renderedLines[#renderedLines + 1] = "-- vm trace: " .. tostring(#vm) .. " operations"
		local histo: { [any]: number } = {}
		for _, entry in ipairs(vm) do
			local op = entry.op
			histo[op] = (histo[op] or 0) + 1
		end
		local ops: { any } = {}
		for op in pairs(histo) do
			ops[#ops + 1] = op
		end
		table.sort(ops, function(x, y)
			return histo[x] > histo[y]
		end)
		local parts: { string } = {}
		for i = 1, math.min(#ops, 20) do
			parts[#parts + 1] = tostring(ops[i]) .. "x" .. tostring(histo[ops[i]])
		end
		renderedLines[#renderedLines + 1] = "-- opcode histogram: " .. table.concat(parts, ", ")
		renderedLines[#renderedLines + 1] = ""
		local LIMIT = 400

		local function show(v: any): string
			if type(v) ~= "table" then
				return tostring(v)
			end

			local keys: { number } = {}
			local total = 0
			for k in pairs(v) do
				total += 1
				if type(k) == "number" and #keys < 4096 then
					keys[#keys + 1] = k
				end
			end
			table.sort(keys)

			if #keys == 0 then

				local names: { string } = {}
				for k, val in pairs(v) do
					names[#names + 1] = string.format("%s=%s", tostring(k), tostring(val))
					if #names >= 8 then
						break
					end
				end
				table.sort(names)
				if #names == 0 then
					return "{opaque" .. tostring(total) .. "}"
				end
				return "{" .. table.concat(names, " ") .. "}"
			end

			local function cell(i: number): string
				local val = v[keys[i]]
				if type(val) == "table" then
					return string.format("[%d]={%d}", keys[i], #val)
				end
				return string.format("[%d]=%s", keys[i], tostring(val))
			end

			local parts: { string } = {}
			local shown = 0
			local i = 1

			while i <= #keys and shown < 8 do
				parts[#parts + 1] = cell(i)
				shown += 1
				i += 1
			end

			if #keys > 10 then
				local tailStart = math.max(i, #keys - 3)
				if tailStart > i then
					parts[#parts + 1] = "..."
				end
				for k = tailStart, #keys do
					parts[#parts + 1] = cell(k)
				end
			end
			local head = table.concat(parts, " ")
			if total > #keys then
				head ..= string.format(" (+%d non-numeric)", total - #keys)
			end
			return "{" .. head .. "}"
		end

		for i = 1, math.min(#vm, LIMIT) do
			local entry = vm[i]

			renderedLines[#renderedLines + 1] = string.format(
				"-- %04d %s  ch=%s  a=%s b=%s c=%s d=%s e=%s",
				i,
				tostring(entry.op),
				tostring(entry.chain),
				show(entry.a),
				show(entry.b),
				show(entry.c),
				show(entry.d),
				show(entry.e)
			)
		end
		if #vm > LIMIT then
			renderedLines[#renderedLines + 1] = "-- ... " .. tostring(#vm - LIMIT) .. " more operations not shown"
		end
		renderedLines[#renderedLines + 1] = ""
		end
	end

	if flags.notes == "true" and sandboxResult and type(sandboxResult.vmTrace) == "table" then
		local seen: { [any]: boolean } = {}
		for _, entry in ipairs(sandboxResult.vmTrace) do
			local regs = entry.a
			local ch = entry.chain
			if type(regs) == "table" and ch ~= nil and not seen[ch] then
				local n = #regs
				if n > 0 then
					seen[ch] = true
					renderedLines[#renderedLines + 1] = string.format(
						"-- ==== chain %s: %d register slots ====", tostring(ch), n)
					local from, to = 1, n
					if n > 2048 then
						from, to = 1, 1024
					end
					for i = from, to do
						local v = regs[i]
						local text
						if type(v) == "table" then
							text = "{...}"
						else
							text = tostring(v)
						end
						renderedLines[#renderedLines + 1] =
							string.format("--  [%d] = %s", i, text)
					end
					if n > to then
						renderedLines[#renderedLines + 1] =
							string.format("-- ... %d more slots not shown", n - to)
					end
					renderedLines[#renderedLines + 1] = ""
				end
			end
		end
	end

	deliver(table.concat(renderedLines, "\n"), flags.out)

	if flags.json then
		local payload = {
			version = Version.build,
			ok = sandboxResult ~= nil,
			error = sandboxError,
			elapsed = os.clock() - started,
			inputBytes = #source,
			detection = if detection then {
				name = detection.name,
				confidence = detection.confidence,
				version = detection.version,
			} else nil,
			stages = if sandboxResult then #sandboxResult.stages else 0,
			vmTrace = if sandboxResult and sandboxResult.vmTrace then #sandboxResult.vmTrace else 0,
			decrypted = if sandboxResult then sandboxResult.decryptedStringCount or 0 else 0,
			constants = if report then report.summary.total else 0,
			exhausted = if sandboxResult then sandboxResult.exhausted else false,
			scriptError = if sandboxResult then sandboxResult.err else nil,
			stageFiles = (function()
				local out: { string } = {}
				if sandboxResult and flags.json then
					for n, stage in ipairs(sandboxResult.stages) do
						if type(stage) == "table" and type(stage.source) == "string" and #stage.source > 0 then
							local first = string.byte(stage.source, 1)
							if first and first >= 0x20 then
								local path = string.gsub(flags.json, "%.json$", "_stage_" .. tostring(n) .. ".lua")
								if pcall(fs.writeFile, path, stage.source) then
									out[#out + 1] = path
								end
							end
						end
					end
				end
				return out
			end)(),
			programFiles = (sandboxResult and sandboxResult.programFiles) or {},
			programVerdict = if sandboxResult then sandboxResult.programVerdict else nil,
			finalEnvCalls = if sandboxResult then sandboxResult.finalEnvCalls else nil,
			firstEnvCalls = if sandboxResult then sandboxResult.firstEnvCalls else nil,
			entryKind = if sandboxResult then sandboxResult.entryKind else nil,
		}
		local okEncode, encoded = pcall(serde.encode, "json", Sanitize.jsonSafe(payload), true)
		if okEncode then
			pcall(fs.writeFile, flags.json :: string, encoded)
		end
	end
	return
end

	local logPath = flags.log
	local logBuffer = ""
	local function logLine(text: string)
		logBuffer ..= "-- [" .. string.format("%.1fs", os.clock() - started) .. "] " .. text .. "\n"
		if logPath then
			pcall(fs.writeFile, logPath, logBuffer)
		end
	end

	local lastFlush = 0
	local partialOutputs: { any }? = nil

	local result: any = nil
	local function flushPartialMeta(info: any)
		if not flags.json or result ~= nil then
			return
		end
		if type(info) == "table" and type(info.outputs) == "table" then
			partialOutputs = info.outputs
		end
		local now = os.clock()
		if now - lastFlush < 2 then
			return
		end
		lastFlush = now
		pcall(function()
			fs.writeFile(flags.json :: string, serde.encode("json", Sanitize.jsonSafe({
				version = Version.build,
				ok = false,
				error = "watchdog killed mid-run (partial results)",
				elapsed = now - started,
				inputBytes = #source,
				outputs = partialOutputs or {},
			}), true))
		end)
	end

if command == "const" or command == "condump" then
	local Constants = require("./analysis/constants")

	local sandboxResult: any = nil
	local sandboxError: string? = nil
	if flags.nodyn ~= "true" then
		local okSandbox, resSandbox = pcall(function()
			return Sandbox.run(source, {
				timeout = tonumber(flags.timeout) or 25,
				maxNest = tonumber(flags.maxnest) or 4,
				traceLimit = math.min(traceLimit, 200000),
				onProgress = function() end,
				zlib = zlib,
				httpCache = flags.cache or "cache",
				allowHttp = false,
				scriptKey = flags.scriptkey,
				maxExplored = 0,
				noInstrument = flags.noinstrument == "true",
				noVmPatch = flags.novmpatch == "true",
				softInstanceCall = flags.softinstance == "true",
				nosoft = flags.nosoft == "true",
			})
		end)
		if okSandbox then
			sandboxResult = resSandbox
		elseif logPath then
			sandboxError = Sanitize.message(tostring(resSandbox))
		end
	end

	local okReport, report = pcall(Constants.analyze, source, sandboxResult)
	if not okReport then
		fail("constants analysis failed: " .. Sanitize.message(tostring(report)))
	end

	local rendered = Constants.render(report)
	if sandboxError and logPath then
		logLine("dynamic pass skipped (sandbox error): " .. sandboxError)
	end
	deliver(rendered, flags.out)

	if flags.json then
		local payload = {
			version = Version.build,
			ok = true,
			dynamicRan = sandboxResult ~= nil,
			elapsed = os.clock() - started,
			inputBytes = #source,
			total = report.summary.total,
			byKind = report.summary.byKind,
			urls = report.summary.urls,
			webhooks = report.summary.webhooks,
			stats = {
				literals = report.stats.literals,
				byteTables = report.stats.byteTables,
				encoded = report.stats.encoded,
				dynamic = report.stats.dynamic,
				stages = report.stats.stages,
			},

			sample = (function()
				local out: { any } = {}
				for i, entry in ipairs(report.constants) do
					if i > 40 then
						break
					end
					out[#out + 1] = {
						value = string.sub(entry.value, 1, 200),
						kind = entry.kind,
						length = entry.length,
						via = entry.sources[1],
					}
				end
				return out
			end)(),
			detection = if detection then {
				name = detection.name,
				confidence = detection.confidence,
				version = detection.version,
			} else nil,
		}
		local okEncode, encoded = pcall(serde.encode, "json", Sanitize.jsonSafe(payload), true)
		if okEncode then
			pcall(fs.writeFile, flags.json :: string, encoded)
		end
	end
	return
end

local function fallbackDump(reason: string): string

	note(reason)
	return Report.HEADER .. "\n"
end

local detection: any = nil
do
	local ok, res = pcall(Detector.detect, source)
	if ok then
		detection = res
	end
end

if logPath then
	logLine("runtime log started (" .. tostring(#source) .. " input bytes, " .. tostring(tonumber(flags.timeout) or 25) .. "s budget)")
end

do
	local blocklistStatus = Blocklist.status()
	if logPath then
		logLine(Blocklist.summary())
	end
	if blocklistStatus.error then
		local ok, stdio = pcall(require, "@lune/stdio")
		if ok then

			pcall(stdio.ewrite, "[envlogger] " .. Blocklist.summary() .. "\n")
		end
	end
end

local function formatProgress(info: any): string
	local parts: { string } = {
		string.format("%s ops", tostring(info.ops or 0)),
		string.format("%s records", tostring(info.records or 0)),
		string.format("%s stages", tostring(info.stages or 0)),
	}
	if type(info.activity) == "string" and info.activity ~= "" then
		parts[#parts + 1] = "| " .. info.activity
	end
	local line = table.concat(parts, " ")
	if info.exhausted then
		line ..= " | BUDGET: " .. tostring(info.exhaustedReason or "exceeded")
	end
	return line
end

local function defaultMaxExplored(bytes: number): number
	if bytes > 1500000 then
		return 0
	elseif bytes > 500000 then
		return 1
	elseif bytes > 200000 then
		return 2
	end
	return 3
end

if command ~= "env" and command ~= "log" then
	fail("unknown command: " .. tostring(command))
end

local analyzerError: string? = nil
do
	local ok, res = pcall(Sandbox.run, source, {
		timeout = tonumber(flags.timeout) or 25,
		maxNest = tonumber(flags.maxnest) or 8,
		traceLimit = traceLimit,
		onProgress = if logPath then function(info: any)
			logLine(formatProgress(info))
			flushPartialMeta(info)
		end else function(info: any)
			flushPartialMeta(info)
		end,
			zlib = zlib,
			httpCache = flags.cache or "cache",
			allowHttp = flags.fetch == "true",
			scriptKey = flags.scriptkey,

		maxExplored = if flags.noexplore == "true"
			then 0
			elseif flags.maxexplored
				then (tonumber(flags.maxexplored) or 3)
				else defaultMaxExplored(#source),
		noInstrument = flags.noinstrument == "true",
		noVmPatch = flags.novmpatch == "true",
		softInstanceCall = flags.softinstance == "true",
		nosoft = flags.nosoft == "true",
		macros = (function()
			if not flags.macros then
				return nil
			end
			local okRead, contents = pcall(fs.readFile, flags.macros)
			if not okRead or type(contents) ~= "string" then
				return nil
			end
			local okDecode, decoded = pcall(serde.decode, "json", contents)
			if okDecode and type(decoded) == "table" then
				return decoded
			end
			return nil
		end)(),
	})
	if ok then
		result = res
	else
		analyzerError = "analyzer error: " .. Sanitize.message(tostring(res))
	end
end
local elapsed = os.clock() - started

if logPath then
	logLine(string.format("run finished in %.1fs (%s)", elapsed, if result then "ok" else "failed"))
end

if command == "log" then
	if result then
		deliver(Report.log(result.trace), flags.out)
	else
		deliver(fallbackDump(analyzerError or "analyzer error"), flags.out)
	end
	return
end

local rendered
if result then
	local ok, res = pcall(Report.render, {
		trace = result.trace,
		stages = result.stages,
		outputs = result.outputs,
		ok = result.ok,
		err = result.err,
		exhausted = result.exhausted,
		exhaustedReason = result.exhaustedReason,
		detection = detection,
		elapsed = elapsed,
		inputBytes = #source,
		source = source,
		explored = result.explored,
		vmTrace = result.vmTrace,
		vmTraceCapped = result.vmTraceCapped,
		undefinedGlobals = result.undefinedGlobals,
		nilCulprit = result.nilCulprit,

		decryptedStrings = result.decryptedStrings,
		decryptedStringCount = result.decryptedStringCount,
		stringTable = result.stringTable,
		unrolledSource = result.unrolledSource,
	}, {
		maxStatements = maxStatements,
		includeOps = flags.noops ~= "true",
		includeStages = flags.nostages ~= "true",
		includeBranches = flags.nospy ~= "true",
		exploreBranches = flags.noexplore ~= "true",
		notes = flags.notes == "true",
	})
	if ok then
		rendered = res
	else
		analyzerError = "analyzer error: " .. Sanitize.message(tostring(res))
		rendered = fallbackDump(analyzerError)
	end

	if flags.beautify == "true" then
		local okBeautify, beautified = pcall(Beautifier.format, rendered)
		if okBeautify and type(beautified) == "string" and #beautified > 0 then
			rendered = beautified
		end
	end
else
	rendered = fallbackDump(analyzerError or "analyzer error")
end
deliver(rendered, flags.out)

if flags.json then
	local artifacts: any = {}
	do
		local okArtifacts, resArtifacts = pcall(Report.artifacts, if result then result.trace else nil)
		if okArtifacts and type(resArtifacts) == "table" then
			artifacts = resArtifacts
		end
	end
	local staticFindings: any = nil
	do
		local okStatic, resStatic = pcall(require("./analysis/static").analyze, source)
		if okStatic then
			staticFindings = resStatic
		end
	end
	local metaError: string? = nil
	local payload = {
		version = Version.build,
		ok = if result then result.ok else false,
		error = if result then result.err else analyzerError,
		exhausted = if result then result.exhausted else false,
		exhaustedReason = if result then result.exhaustedReason else nil,
		elapsed = elapsed,
		inputBytes = #source,
		operations = if result then result.trace.count else 0,
		dropped = if result then result.trace.dropped else 0,
		stages = if result then #result.stages else 0,

		programs = if result then (function()
			local out: { any } = {}
			for _, stage in ipairs(result.stages) do
				if type(stage.origin) == "string" and stage.origin == "buffer" and type(stage.data) == "string" then
					out[#out + 1] = { bytes = #stage.data }
				end
			end
			return out
		end)() else {},

		stageFiles = (function()
			local out: { string } = {}
			local STAGE_INLINE_BYTES = 8192
			if result then
				for n, stage in ipairs(result.stages) do
					if type(stage.source) == "string" and #stage.source > STAGE_INLINE_BYTES then
						local first = string.byte(stage.source, 1)
						if first and first >= 0x20 then
							local path = string.gsub(flags.json, "%.json$", "_stage_" .. tostring(n) .. ".lua")
							if pcall(fs.writeFile, path, stage.source) then
								out[#out + 1] = path
							end
						end
					elseif stage.origin == "buffer" and type(stage.data) == "string" and #stage.data > 0 then
						local path = string.gsub(flags.json, "%.json$", "_program_" .. tostring(n) .. ".bin")
						if pcall(fs.writeFile, path, stage.data) then
							out[#out + 1] = path
						end
					end
				end
			end
			return out
		end)(),
		outputs = if result then result.outputs else {},
		outputsDropped = if result then (result.outputsDropped or 0) else 0,
		static = staticFindings,
		detection = if detection then {
			name = detection.name,
			confidence = detection.confidence,
			strategy = detection.strategy,
			score = detection.score,
			version = detection.version,
		} else nil,
		artifacts = artifacts,
		vmTrace = if result and result.vmTrace and #result.vmTrace > 0 then {
			count = #result.vmTrace,
			capped = result.vmTraceCapped == true,
			first = (function()
				local out: { any } = {}
				for i = 1, math.min(#result.vmTrace, 20) do
					local st = result.vmTrace[i]
					out[#out + 1] = { op = st.op, a = st.a, b = st.b }
				end
				return out
			end)(),
		} else nil,
	}

	local ok, encoded = pcall(serde.encode, "json", Sanitize.jsonSafe(payload), true)
	if ok then
		local writeOk, writeErr = pcall(fs.writeFile, flags.json, encoded)
		if not writeOk then
			metaError = "sidecar write failed: " .. tostring(writeErr)
		end
	else
		metaError = "sidecar encode failed: " .. tostring(encoded)
	end
	if metaError then

		print("warning: " .. metaError)
		local fallbackPayload = {
			version = Version.build,
			ok = false,
			error = metaError,
			elapsed = elapsed,
			inputBytes = #source,
		}
		local okFallback, encodedFallback = pcall(serde.encode, "json", fallbackPayload, true)
		if okFallback then
			pcall(fs.writeFile, flags.json, encodedFallback)
		end
	end
end
