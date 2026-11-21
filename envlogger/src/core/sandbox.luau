local luau = require("@lune/luau")
local fs = require("@lune/fs")
local Deobfuscation = require("./deobfuscation")
local Fidelity = require("../env/fidelity")

local MAX_BUFFER_STAGE_BYTES = 2097152

local AntiNil = require("./antinil")
local Control = require("../env/control")
local Datatypes = require("../env/datatypes")
local Instrument = require("./instrument")
local PrngTrace = require("../env/prngtrace")
local SrcEdit = require("./srcedit")
local TaskState = require("../env/taskstate")
local Roblox = require("../env/roblox")
local Sanitize = require("./sanitize")
local Serializer = require("./serializer")
local Signal = require("../env/signal")
local Spy = require("./spy")
local Symbol = require("./symbol")
local Stdlib = require("../env/stdlib")
local Trace = require("./trace")

local Sandbox = {}

local ssDiagTotals: { [string]: any } = { events = 0, dropBase = 0, softKey = 0, nilKey = 0, nilVal = 0 }

local OP_SYMBOLS: { [string]: string } = {
	eq = "==",
	ne = "~=",
	lt = "<",
	le = "<=",
	gt = ">",
	ge = ">=",
}

export type Options = {

	maxNest: number?,

	timeout: number?,

	traceLimit: number?,

	stagePatch: { [number]: string }?,

	zlib: any?,

	httpCache: string?,

	allowHttp: boolean?,

	httpMaxBytes: number?,

	maxExplored: number?,

	onProgress: ((info: { [string]: any }) -> ())?,

	noInstrument: boolean?,
	gethuiMode: string?,
	nosoft: boolean?,
	noVmPatch: boolean?,
	softInstanceCall: boolean?,

	macros: { [string]: any }?,

	scriptKey: string?,
}

export type Stage = {

	nest: number,

	source: string,

	origin: string,

	executed: boolean,

	data: string?,
}

export type Result = {
	trace: Trace.Class,
	stages: { Stage },
	outputs: { { channel: string, text: string } },

	outputsDropped: number?,

	outputTotalBytes: number?,

	ok: boolean,

	err: string?,

	exhausted: boolean,

	exhaustedReason: string?,

	explored: { any }?,

	vmTrace: { any }?,

	vmTraceCapped: boolean?,

	undefinedGlobals: { { name: string, count: number } }?,

	nilCulprit: string?,

	bxorLog: { { number } }?,
}

local function se(message: any): string
	return Sanitize.message(message)
end

local function looksLikeSource(text: string): boolean
	if #text == 0 then
		return false
	end

	local first = string.byte(text, 1)
	if first and first < 0x20 and first ~= 0x09 and first ~= 0x0A and first ~= 0x0D then
		return false
	end
	return true
end

local function isL(text: string): boolean
	if #text < 1000 then return false end

	if string.find(text, "Ef=function", 1, true) ~= nil
		and string.find(text, "while v do if I<=", 1, true) ~= nil then
		return true
	end

	if (string.find(text, "bd=function", 1, true) ~= nil or string.find(text, "xd=function", 1, true) ~= nil)
		and string.find(text, "while %w+ do if %w+<=", 1) ~= nil then
		return true
	end

	if string.find(text, "return setmetatable", 1, true) ~= nil
		and string.find(text, "[47]=function", 1, true) ~= nil
		and string.find(text, "buffer.fromstring", 1, true) ~= nil then
		return true
	end

	if string.find(text, "return setmetatable", 1, true) ~= nil
		and string.find(text, "buffer.readf64", 1, true) ~= nil then
		return true
	end

	if string.find(text, "until false", 1, true) ~= nil
		and string.find(text, "repeat%s+%w+,%w+,%w+,%w+=%w+:%w+%b()") ~= nil then
		return true
	end

	if string.find(text, "while true do if %w+==") ~= nil
		and string.find(text, "elseif %w+==") ~= nil then
		return true
	end

	local hasBanner = string.find(text, "Luraph Obfuscator", 1, true) ~= nil
		or string.find(text, "Luraph decompression error", 1, true) ~= nil
		or string.find(text, "does your environment support load/loadstring?", 1, true) ~= nil
	if hasBanner then
		return true
	end

	local hasDispatch = string.find(text, "while true do if", 1, true) ~= nil
		or string.find(text, "repeat if", 1, true) ~= nil
		or string.find(text, "while (%w+) do if (%w+)<=", 1) ~= nil
	if hasDispatch then
		if string.find(text, "string.unpack", 1, true) ~= nil
			or string.find(text, "buffer.readu8", 1, true) ~= nil
			or string.find(text, "buffer.readu32", 1, true) ~= nil
			or string.find(text, "string.byte", 1, true) ~= nil then

			if string.find(text, "return(function", 1, true) ~= nil
				or string.find(text, "return({", 1, true) ~= nil
				or string.find(text, "LPH@", 1, true) ~= nil
				or string.find(text, "LPH#", 1, true) ~= nil
				or string.find(text, "setfenv", 1, true) ~= nil then
				return true
			end
		end
	end

	if string.find(text, "Luraph decompression", 1, true) ~= nil
		and string.find(text, "loadstring", 1, true) ~= nil then
		return true
	end

	return false
end

local function isF(text: string): boolean
	if #text < 500 then return false end
	if string.find(text, "Fulcrum", 1, true) ~= nil then return true end
	if string.find(text, "pX.NQw", 1, true) ~= nil then return true end
	return false
end

local function isM(text: string): boolean
	if #text < 500 then return false end

	if string.find(text, ":ta(", 1, true) ~= nil
		or string.find(text, "}:M(", 1, true) ~= nil
		or (string.sub(text, 1, 8) == "return({" and string.find(text, "}:M(", 1, true) ~= nil) then
		return true
	end

	if string.find(text, "MoonVeil", 1, true) ~= nil
		and (string.find(text, "while true do", 1, true) ~= nil
			or string.find(text, "repeat if ", 1, true) ~= nil) then
		return true
	end
	return false
end

local function pm(text: string): string

	local out = string.gsub(
		text,
		"while true do",
		"while true do __glassluau_vm_trace();"
	)

	if out == text then
		out = string.gsub(
			text,
			"repeat if (%w+)([<>])",
			"repeat %1=__glassluau_vm_trace(%1) or %1; if %1%2"
		)
	end

	if out == text then
		return text
	end

	out = string.gsub(out, "(%[%d+%]=)buffer%.", "%1__glassluau_buf.")
	out = string.gsub(out, "(%[%d+%]=)vector%.", "%1__glassluau_vec.")
	out = string.gsub(out, "([^%w_])vector%.create", "%1__glassluau_vec.create")
	out = string.gsub(out, "([^%w_])vector%.zero", "%1__glassluau_vec.zero")
	out = string.gsub(out, "(%[%d+%]=)table%.create", "%1__glassluau_tbl.create")
	out = string.gsub(out, "(%[%d+%]=)table%.move", "%1__glassluau_tbl.move")
	return out
end

local function pf(text: string): string
	return text
end

local function pd(text: string): string

	local okL, LuraphExtract = pcall(require, "./luraph_extract")
	if okL and LuraphExtract and type(LuraphExtract.patchDispatcher) == "function" then
		local out = LuraphExtract.patchDispatcher(text)
		if out ~= text then
			return out
		end
	end

	local out = string.gsub(
		text,
		"while v do if I%<=",
		"while v do __glassluau_vm_trace(I,p,y,L,O,V,f,e);if I<="
	)

	if out == text then
		out = string.gsub(
			text,
			"while (%w+) do if (%w+)<=(%d+)( then)",
			"while %1 do __glassluau_vm_trace(); if %2<=%3%4"
		)
	end
	if out == text then

		out = string.gsub(
			text,
			"while (%w+) do if (%w+)<=(%d+)",
			"while %1 do __glassluau_vm_trace(); if %2<=%3"
		)
	end
	if out == text then

		out = string.gsub(
			text,
			"while true do if (%w+)<=",
			"while true do __glassluau_vm_trace(); if %1<="
		)
	end
	if out == text then
		return text
	end

	out = string.gsub(out, "while true do", "while true do __glassluau_vm_guard();")

	out = string.gsub(out, "(%[%d+%]=)buffer%.", "%1__glassluau_buf.")

	out = string.gsub(out, "(%[%d+%]=)vector%.", "%1__glassluau_vec.")
	out = string.gsub(out, "([^%w_])vector%.create", "%1__glassluau_vec.create")
	out = string.gsub(out, "([^%w_])vector%.zero", "%1__glassluau_vec.zero")

	out = string.gsub(out, "(%[%d+%]=)table%.create", "%1__glassluau_tbl.create")
	out = string.gsub(out, "(%[%d+%]=)table%.move", "%1__glassluau_tbl.move")
	return out
end

function Sandbox.run(source: string, options: Options?): Result

	if string.sub(source, 1, 3) == "\239\187\191" then
		source = string.sub(source, 4)
	end

	local settings = options or {}
	local maxNest = settings.maxNest or 8
	local explicitTimeout = tonumber(settings.timeout)
	local timeout = if explicitTimeout ~= nil then explicitTimeout else 25

	local stagePatch = settings.stagePatch

	local programDir = settings.programDir
	if type(programDir) == "string" and #programDir > 0 then
		pcall(fs.mkdir, programDir)
	end
		local programFiles: { string } = {}
		local programVerdict: string? = nil
		local finalEnvCalls: string? = nil
		local firstEnvCalls: string? = nil
		local entryKind: string? = nil

		local argProgram: string = ""

	if isL(source) and explicitTimeout == nil then
		timeout = 300
	end

	local startClock = os.clock()

	local function runOnce(forcedBranches: { [number]: boolean }?): any
		Signal.reset()
		local trace = Trace.new(settings.traceLimit or 200000)
		local stages: { Stage } = {}
		local outputs: { { channel: string, text: string } } = {}

		local outputTotalBytes = 0
		local outputsDropped = 0
		local OUTPUT_TOTAL_BUDGET = 1572864

		local function capOutputText(text: string): string
			if #text > 16384 then
				return string.sub(text, 1, 16384) .. "\n-- (output truncated at 16KB)"
			end
			return text
		end

		local function pushOutput(channel: string, text: string)
			local scrubbed = Sanitize.secrets(capOutputText(text))
			if outputTotalBytes + #scrubbed > OUTPUT_TOTAL_BUDGET then
				outputsDropped += 1
				return
			end
			outputTotalBytes += #scrubbed
			outputs[#outputs + 1] = { channel = channel, text = scrubbed }
			if #outputs > 512 then
				local removed = table.remove(outputs, 1)
				outputTotalBytes -= #(removed and removed.text or "")
			end
		end
		local exhausted = false
		local exhaustedReason: string? = nil

		local sharedGenvProxy: any = nil

		local sharedGetgenvGlobals: { [string]: any } = {}

		local VM_TRACE_MAX = 60000
		local vmTrace: { any } = {}
		local vmTraceCapped = false

		local softInstanceCall = settings.softInstanceCall == true

		local antiNil = AntiNil.new()

		local decryptedStrings: { string } = {}
		local decryptedStringCount = 0

		local bxorLog: { { number } } = {}
		local bxorLogCount = 0

		local stringTable: { [string]: string } = {}

		local valueNames: { [any]: string } = setmetatable({}, { __mode = "k" })

		local function overBudget(): boolean
			if exhausted then
				return true
			end
			if os.clock() - startClock > timeout then
				exhausted = true
				exhaustedReason = "time budget exceeded"
				return true
			end
			return false
		end

		local opCount = 0
		local lastProgressAt = os.clock()

		local undefinedReads: { [string]: number } = {}
		local undefinedOrder: { string } = {}
		local lastUndefined: string? = nil
		local nilCulprit: string? = nil
		local MAX_UNDEFINED_NAMES = 128

		local function noteUndefined(key: any)
			if type(key) ~= "string" then
				return
			end
			if string.sub(key, 1, 12) == "__glassluau_" or string.sub(key, 1, 7) == "__FUHD_"
				or string.sub(key, 1, 6) == "__LPH_" then
				return
			end
			if key == "io" or key == "fs" or key == "process" or key == "package" then
				return
			end
			local seen = undefinedReads[key]
			if seen then
				undefinedReads[key] = seen + 1
			elseif #undefinedOrder < MAX_UNDEFINED_NAMES then
				undefinedReads[key] = 1
				undefinedOrder[#undefinedOrder + 1] = key
			else

				lastUndefined = key
				return
			end
			lastUndefined = key
		end

		local function undefinedList(): { { name: string, count: number } }
			local list = {}
			for _, name in ipairs(undefinedOrder) do
				list[#list + 1] = { name = name, count = undefinedReads[name] or 0 }
			end
			table.sort(list, function(a, b)
				if a.count == b.count then
					return a.name < b.name
				end
				return a.count > b.count
			end)
			return list
		end

		local function emitProgress(force: boolean?): boolean
			local callback = settings.onProgress
			if not callback then
				return false
			end
			local now = os.clock()
			if not force and now - lastProgressAt < 0.5 then
				return false
			end
			lastProgressAt = now

			local activity = ""
			local n = #trace.records
			if n > 0 then
				local last = trace.records[n]
				if last then
					if last.kind == "loadstring" then
						activity = string.format("loadstring stage captured (%d bytes)", #(last.expression or ""))
					else
						activity = last.expression or ""
					end
				end
			end
			if #activity > 120 then
				activity = string.sub(activity, 1, 120) .. "..."
			end
			local ok, err = pcall(callback, {
				elapsed = now - startClock,
				ops = opCount,
				records = n,
				stages = #stages,
				activity = activity,
				exhausted = exhausted,
				exhaustedReason = exhaustedReason,

				outputs = (function()
					local tail: { any } = {}
					local from = math.max(1, #outputs - 199)
					for i = from, #outputs do
						tail[#tail + 1] = outputs[i]
					end
					return tail
				end)(),
			})
			return ok and err == nil
		end

		local function opCheck(): boolean
			if exhausted then
				return true
			end
			opCount += 1
			if opCount % 256 ~= 0 then
				return false
			end
			emitProgress(false)
			return overBudget()
		end

		local BUDGET_ERROR = "sandbox budget exceeded"
		local function abort(): never
			error(BUDGET_ERROR)
		end

		local branchCounter = 0

		local unknownOpCounter = 0
		local lastBranchOpCounter = 0

		local setfenvMap: { [any]: any } = {}

		local scriptEnvs: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

		local realSetfenv = setfenv
		local realGetfenv = getfenv
		local realDebugInfo = debug.info
		local realSethook: any = (debug :: any).sethook
		local realGetmetatable: any = getmetatable
		local realSetmetatable: any = setmetatable

		local function isScriptClosure(fn: any): boolean
			if type(fn) ~= "function" then
				return false
			end
			local ok, src = pcall(realDebugInfo, fn, "s")
			return ok and src == '[string ""]'
		end

		local function applyScriptFenv(fn: any, replacement: any)
			if type(replacement) ~= "table" or not isScriptClosure(fn) then
				return
			end
			if pcall(realSetfenv, fn, replacement) then
				scriptEnvs[replacement] = true
			end
		end

		local function resolveScriptLevel(wanted: number): any
			if wanted < 1 then
				return nil
			end
			local seen = 0
			for depth = 2, 26 do
				local ok, fn = pcall(realDebugInfo, depth, "f")
				if not ok or fn == nil then
					return nil
				end
				if isScriptClosure(fn) then
					seen += 1
					if seen >= wanted then
						return fn
					end
				end
			end
			return nil
		end

		local buildEnvironment: (nest: number) -> any

local function describeStructuralImbalance(chunk: string): string?
	local okTok, toks = pcall(Instrument.tokenize, chunk)
	if not okTok or type(toks) ~= "table" or #toks == 0 or #toks > 2000000 then
		return nil
	end
	local count: { [string]: number } = {}
	for index, tok in ipairs(toks) do
		if tok.kind == "kw" then
			count[tok.raw] = (count[tok.raw] or 0) + 1

			if tok.raw == "end" then
				local nextTok = toks[index + 1]
				if nextTok and nextTok.kind == "sym"
					and (nextTok.raw == ":" or nextTok.raw == "." or nextTok.raw == "("
						or nextTok.raw == "[" or nextTok.raw == "{") then
					return string.format(
						"the input looks corrupted or truncated: `end%s...` is not valid Luau"
							.. " (an opening `(function` was likely lost in the paste) -- re-export"
							.. " or re-copy the whole script",
						nextTok.raw
					)
				end
			end
		end
	end

	local needEnd = (count["function"] or 0) + (count["if"] or 0) + (count["do"] or 0)
	local ends = count["end"] or 0
	local surplus = ends - needEnd
	if surplus > 0 then
		return string.format(
			"the input looks corrupted or truncated: %d more `end` than blocks to"
				.. " close -- this is not valid Luau and no parser can run it; re-export"
				.. " or re-copy the whole script",
			surplus
		)
	end
	return nil
end

local function cc(chunk: string, env: any): (any?, string?)

	local runChunk = chunk

	local function compiles(text: string): boolean
		local okT, fnT = pcall(luau.load, text, { debugName = "cccheck" })
		return okT and fnT ~= nil
	end

	local lowered = Instrument.lowerBitwise(runChunk)
	if lowered then
		runChunk = lowered
	end
		if isL(chunk) then
			local patched = pd(chunk)

			if patched ~= chunk then
				local LuraphExtract = require("./luraph_extract")
				local withStrTrace = LuraphExtract.patchByteConcat(patched)
				if withStrTrace ~= patched then
					patched = withStrTrace
				end
				if compiles(patched) then
					runChunk = patched
					trace:push("note", "Luraph branch entered - dispatch/strace patched", nest)
				else
					trace:push("note", "vm patch rejected: result does not compile; keeping unpatched chunk", nest)
				end
			else
				trace:push("note", "Luraph branch entered - no dispatcher match (loader shell?)", nest)
			end
		elseif (isM(chunk) or string.find(chunk, "MoonVeil", 1, true) ~= nil) and settings.noVmPatch ~= true then
		trace:push("note", "MoonVeil branch entered", nest)
		local patched = pm(chunk)
		if patched ~= chunk and compiles(patched) then
			runChunk = patched
		elseif patched ~= chunk then
			trace:push("note", "MoonVeil patch rejected: result does not compile", nest)
		end
		do
			local wrapped, wrapErr = SrcEdit.wrapFunctions(runChunk, Instrument.tokenize)
			if wrapped and wrapped ~= runChunk and compiles(wrapped) then
				runChunk = wrapped
				trace:push("note", "wrapped(MoonVeil) " .. tostring((function() local c=0 for _ in string.gmatch(wrapped, "__wrapFunc") do c+=1 end return c end)()) .. " functions for FindFirstChild hardening", nest)
			else
				trace:push("note", "wrap skipped: " .. tostring(wrapErr or (wrapped and "result does not compile" or "no change")), nest)
			end
		end
	elseif isF(chunk) and settings.noVmPatch ~= true then
		trace:push("note", "Fulcrum branch entered", nest)
		local patched = pf(chunk)
		if patched ~= chunk then
			runChunk = patched
		end
		do
			local wrapped, wrapErr = SrcEdit.wrapFunctions(runChunk, Instrument.tokenize)
			if wrapped and wrapped ~= runChunk and compiles(wrapped) then
				runChunk = wrapped
				trace:push("note", "wrapped(Fulcrum) " .. tostring((function() local c=0 for _ in string.gmatch(wrapped, "__wrapFunc") do c+=1 end return c end)()) .. " functions for key bypass", nest)
			else
				trace:push("note", "wrap skipped: " .. tostring(wrapErr or (wrapped and "result does not compile" or "no change")), nest)
			end
		end
	end

	do
		local okG, guarded, gerr, gcount = pcall(Instrument.guardArith, runChunk)
		if okG and type(guarded) == "string" and (gcount :: number) > 0 and compiles(guarded) then
			local withPre = Instrument.GUARD_PRELUDE .. "\n" .. guarded
			if compiles(withPre) then
				runChunk = withPre
				trace:push("note", "arith guarded " .. tostring(gcount) .. " sites", nest)
			else
				runChunk = guarded
				trace:push("note", "arith guarded " .. tostring(gcount) .. " sites (no prelude)", nest)
			end
		elseif not okG then
			trace:push("note", "arith guard skipped: " .. tostring(gerr), nest)
		end
	end
	if softInstanceCall and not settings.nosoft then
		local wrapped2, wrapErr2 = SrcEdit.wrapFunctions(runChunk, Instrument.tokenize)
		if wrapped2 and wrapped2 ~= runChunk and compiles(wrapped2) then
			runChunk = wrapped2
			trace:push("note", "wrapped(soft) " .. tostring((function() local c=0 for _ in string.gmatch(wrapped2, "__wrapFunc") do c+=1 end return c end)()) .. " funcs", nest)
		end
	end
	do

		if isF(chunk) then
			trace:push("note", "safeIndex skipped for Fulcrum (pX VM)", nest)
		else
			local softProps = softInstanceCall and not settings.nosoft

			if softProps and isL(chunk) then
				softProps = false
			end
			local safeWrapped, safeErr = SrcEdit.wrapSafeIndexing(runChunk, Instrument.tokenize, softProps)
			if safeWrapped and safeWrapped ~= runChunk and compiles(safeWrapped) then
				runChunk = safeWrapped
				trace:push("note", "safeIndex wrapped " .. tostring((function() local c=0 for _ in string.gmatch(safeWrapped, "__FUHD_SAFE") do c+=1 end return c end)()) .. " sites", nest)
			else
				trace:push("note", "safeIndex skipped: " .. tostring(safeErr or (safeWrapped and "result does not compile" or "no change")), nest)
			end
		end
	end

		local function debugNameFor(text: string): string
			local flat = text:gsub("[\r\n]+", " ")
			if #flat > 60 then
				flat = string.sub(flat, 1, 57) .. "..."
			end
			return "[string \"" .. flat .. "\"]"
		end

		local function tryCompile(text: string): (any?, boolean)
			local ok, fn = pcall(luau.load, text, {
				environment = env,
				injectGlobals = false,

				debugName = "=" .. debugNameFor(text),

				codegenEnabled = true,
			})
			if ok and fn then

				Stdlib.chunkSources[debugNameFor(text)] = text
			end
			return fn, ok
		end

		if settings.noInstrument then
			local fn, ok = tryCompile(runChunk)
			if ok and fn then
				return fn, nil
			end
		end

		if string.find(runChunk, "__glassluau_vm_trace", 1, true) then
			local fn, ok = tryCompile(runChunk)
			if ok and fn then
				return fn, nil
			end
		end

		local transformed = Instrument.apply(runChunk, { operators = true })
		if transformed then
			local fn, ok = tryCompile(transformed)
			if ok and fn then
				if settings.debugStages == "true" then
					print("STAGEPROBE rung=full bytes=" .. tostring(#runChunk))
				end
				return fn, nil
			end
		end
		local noOperators = Instrument.apply(runChunk, { operators = false })
		if noOperators and noOperators ~= transformed then
			local fn, ok = tryCompile(noOperators)
			if ok and fn then
				if settings.debugStages == "true" then
					print("STAGEPROBE rung=noops bytes=" .. tostring(#runChunk))
				end
				return fn, nil
			end
		end
		local loopsOnly = Instrument.applyLoops(runChunk)
		if loopsOnly and loopsOnly ~= transformed and loopsOnly ~= noOperators then
			local fn, ok = tryCompile(loopsOnly)
			if ok and fn then
				if settings.debugStages == "true" then
					print("STAGEPROBE rung=loops bytes=" .. tostring(#runChunk))
				end
				return fn, nil
			end
		end

		local fn, ok = tryCompile(runChunk)
		if ok then
			if settings.debugStages == "true" then
				print("STAGEPROBE rung=raw bytes=" .. tostring(#runChunk))
			end
			return fn, nil
		end

		local normalizedChunk: string? = nil
		if string.find(chunk, "[\226\128\156\226\128\157\226\128\152\226\128\153]") then
			local text = chunk
			text = string.gsub(text, "\226\128\156", "\"")
			text = string.gsub(text, "\226\128\157", "\"")
			text = string.gsub(text, "\226\128\152", "'")
			text = string.gsub(text, "\226\128\153", "'")
			normalizedChunk = text
		end
		if normalizedChunk then
			local nFn, nOk = tryCompile(normalizedChunk)
			if nOk then
				return nFn, nil
			end
			local nTransformed = Instrument.apply(normalizedChunk, { operators = true })
			if nTransformed then
				local nFn2, nOk2 = tryCompile(nTransformed)
				if nOk2 then
					return nFn2, nil
				end
			end

			local nNoOps = Instrument.apply(normalizedChunk, { operators = false })
			if nNoOps and nNoOps ~= nTransformed then
				local nFn3, nOk3 = tryCompile(nNoOps)
				if nOk3 then
					return nFn3, nil
				end
			end
		end

		local raw = tostring(fn)
		local firstLine = string.match(raw, "^([^\n]+)") or raw
		local rest = string.sub(raw, #firstLine + 1)
		local imbalance = describeStructuralImbalance(chunk)
		if imbalance then
			firstLine = firstLine .. " -- " .. imbalance
		end

		if runChunk ~= chunk then
			local pFn, pOk = tryCompile(chunk)
			if pOk and pFn then
				trace:push("note", "all transforms failed to compile; executing pristine chunk without instrumentation", nest)
				return pFn, nil
			end
		end
		return nil, firstLine .. rest
	end

	local function execute(chunk: string, nest: number, origin: string, envOverride: any?, rootProxy: any?, ...: any): (boolean, ...any)
		if nest > maxNest then
			exhausted = true
			exhaustedReason = "maximum nesting depth reached"
			return false, "nest limit"
		end
		if overBudget() then
			return false, "budget"
		end

		local baseEnv = buildEnvironment(nest, rootProxy)
		local env = baseEnv

		if envOverride and type(envOverride) == "table" then
			local overrideMeta = getmetatable(envOverride)
			local fallback = if type(overrideMeta) == "table" then overrideMeta.__index else nil

			local scopedEnv = setmetatable({}, {
				__index = function(_, key)
					local direct = rawget(envOverride, key)
					if direct ~= nil then
						return direct
					end
					if type(fallback) == "function" then
						local okValue, value = pcall(fallback, envOverride, key)
						if okValue and value ~= nil then
							return value
						end
					elseif type(fallback) == "table" and fallback ~= nil then
						local okValue, value = pcall(function()
							return (fallback :: any)[key]
						end)
						if okValue and value ~= nil then
							return value
						end
					end

					return baseEnv[key]
				end,
				__newindex = function(_, key, value)
					baseEnv[key] = value
				end,
			})
			for key, value in pairs(envOverride) do
				scopedEnv[key] = value
			end
			env = scopedEnv
		end

		do
			local signature = string.sub(chunk, 1, 4)
			local precompiled: string? = nil
			if signature == "\27Lua" then
				local version = string.byte(chunk, 5)
				local name = if version == 0x51 then "Lua 5.1"
					elseif version == 0x52 then "Lua 5.2"
					elseif version == 0x53 then "Lua 5.3"
					elseif version == 0x54 then "Lua 5.4"
					else "Lua (version byte " .. tostring(version) .. ")"
				precompiled = name .. " precompiled bytecode"
			elseif string.sub(chunk, 1, 3) == "\27LJ" then
				precompiled = "LuaJIT precompiled bytecode"
			end
			if precompiled then
				local why = string.format(
					"stage is %s (%d bytes), not source -- Luau cannot load it, and neither can a Roblox executor",
					precompiled,
					#chunk
				)
				trace:push("note", why, nest, { origin = origin })
				return false, why
			end
		end
		local compiled: any = nil
		local compileError: string? = nil
		local okCompile, pcallErr = pcall(function()
			compiled, compileError = cc(chunk, env)
		end)

		local function firstLine(text: string?): string?
			if not text then
				return nil
			end
			local line = string.match(text, "^([^\n]+)")
			return line or text
		end
		if not okCompile then
			local detail = firstLine(tostring(pcallErr)) or firstLine(tostring(compiled)) or "unknown error"
			compileError = "stage did not compile: " .. detail
		elseif not compiled then
			compileError = "stage did not compile" .. (compileError and (": " .. (firstLine(compileError) or "")) or "")
		end
		if compileError then
			trace:push("note", compileError, nest, { origin = origin })
			return false, compileError
		end
		local funcMt = {
			__index = function(_, key: any): any
				if key == "FindFirstChild" or key == "FindFirstChildOfClass" or key == "FindFirstChildWhichIsA" or key == "WaitForChild" or key == "GetService" or key == "GetChildren" or key == "GetDescendants" then
					return function(): any
						return nil
					end
				end
				return nil
			end,
		}

		if realSethook and not settings.noInstrument and not softInstanceCall then
			pcall(function()
				local hook = function()
					for depth = 2, 12 do
						for idx = 1, 30 do
							local okN, name, val = pcall(realDebugInfo, depth, idx, "n")
							if not okN or name == nil then
								break
							end
							if type(val) == "function" and realGetmetatable(val) == nil then
								pcall(realSetmetatable, val, funcMt)
							end
						end
						for idx = 1, 20 do
							local okU, name, val = pcall(realDebugInfo, depth, idx, "u")
							if not okU or name == nil then
								break
							end
							if type(val) == "function" and realGetmetatable(val) == nil then
								pcall(realSetmetatable, val, funcMt)
							end
						end
					end
				end
				realSethook(hook, "l")
			end)
		end
		local results = table.pack(xpcall(compiled, function(err)
			local msg = tostring(err)

			local bt = se(debug.traceback(msg, 2))
			if type(bt) == "string" and #bt > 0 then
				local short = bt
				if #short > 2000 then
					short = string.sub(short, 1, 2000) .. "..."
				end
				trace:push("note", "crash trace: " .. short, nest, { origin = origin })

				local localsDump = {}
				for depth = 2, 8 do
					local okInfo, fn = pcall(realDebugInfo, depth, "f")
					if not okInfo or fn == nil then
						break
					end
					local parts = {}
					local idx = 1
					while idx <= 12 do
						local okSlot, name, value = pcall(realDebugInfo, depth, idx, "n")
						if not okSlot or name == nil then
							break
						end
						parts[#parts + 1] = tostring(name) .. "=" .. type(value)
						idx += 1
					end
					if #parts > 0 then
						localsDump[#localsDump + 1] = "frame " .. se(tostring(fn)) .. ": " .. table.concat(parts, ", ")
					end
				end
				do
					local joined = table.concat(localsDump, " | ")
					if #joined == 0 then joined = "(no frames resolved)" end
					if #joined > 1500 then
						joined = string.sub(joined, 1, 1500) .. "..."
					end
					trace:push("note", "crash locals: " .. joined, nest, { origin = origin })
				end
				do

					local okEnv, StdlibMod = pcall(require, "../env/stdlib")
					if okEnv and StdlibMod and StdlibMod.envCallLog then
						local okLog, logText = pcall(StdlibMod.envCallLog)
						if okLog and type(logText) == "string" then
							if #logText > 2800 then
								logText = "..." .. string.sub(logText, #logText - 2800)
							end
							trace:push("note", "env call log: " .. logText, nest, { origin = origin })
						end
					end
				end
			end

			local isNilError = msg:find("attempt to call a nil value", 1, true)
				or msg:find("attempt to index a nil value", 1, true)
				or msg:find("attempt to perform arithmetic on a nil value", 1, true)
				or msg:find("attempt to perform arithmetic", 1, true) and msg:find("nil", 1, true)
				or msg:find("attempt to concatenate a nil value", 1, true)
				or msg:find("attempt to concatenate", 1, true) and msg:find("nil", 1, true)
				or msg:find("attempt to compare a nil value", 1, true)
				or msg:find("attempt to compare", 1, true) and msg:find("nil", 1, true)
				or msg:find("attempt to index", 1, true) and msg:find("nil", 1, true)
				or msg:find("attempt to call", 1, true) and msg:find("nil", 1, true)
				or msg:find("attempt to perform", 1, true) and msg:find("nil", 1, true)
			if isNilError then
				trace:push("note", "nil recovery: " .. msg, nest, { origin = origin })
				antiNil:log(nest, "runtime", nil, msg)

				if nilCulprit == nil then
					nilCulprit = lastUndefined
				end
			end
			return msg
		end, ...))
		if realSethook then pcall(realSethook, nil :: any) end
		if not results[1] then
			return false, results[2]
		end

		return true, table.unpack(results, 2, results.n)
	end

	function buildEnvironment(nest: number, rootEnvProxy: any?): any
		local config = {
			trace = trace,
			nest = nest,
			maxDepth = 24,
			checkBudget = opCheck,
			softInstanceCall = softInstanceCall,
			gethuiMode = settings.gethuiMode,
		}

		local function resolveGlobalName(value: any): string?
			return valueNames[value]
		end

		local globals: { [string]: any }

		local function resolveEnvName(value: any): string?
			if type(value) ~= "function" then
				return nil
			end
			for key, candidate in pairs(globals) do
				if candidate == value then
					return tostring(key)
				end
			end
			return nil
		end

		local onHostile = function(message: string)
			if opCheck() then
				abort()
			end
			trace:push("output", message, nest, {
				channel = "print",
				args = { { text = message, isString = true } },
			})			pushOutput("print", message)
			end

		local clock = { elapsed = 0 }

		local taskState = TaskState.new()

		Stdlib.setBudgetHook(overBudget)

		globals = Stdlib.build({
			zlib = settings.zlib,
			onHostile = onHostile,
			trace = trace,
			nest = nest,
			clock = clock,
			taskState = taskState,
			checkBudget = opCheck,
		})

		for key, value in pairs(Control.build({
			trace = trace,
			nest = nest,			onOutput = function(channel: string, text: string)
				if opCheck() then
					abort()
				end
				pushOutput(channel, text)
				end,
			checkBudget = opCheck,
			resolveName = resolveGlobalName,
		})) do
			globals[key] = value
		end

		for key, value in pairs(Datatypes.build()) do
			globals[key] = value
		end

		for key, value in pairs(Roblox.build({
			trace = trace,
			nest = nest,
			config = config,
			httpCache = settings.httpCache,
			allowHttp = settings.allowHttp,
			httpMaxBytes = settings.httpMaxBytes,
			checkBudget = opCheck,
			onHostile = onHostile,
			clock = clock,
			taskState = taskState,
			macros = settings.macros,
			scriptKey = settings.scriptKey,
		})) do
			globals[key] = value
		end

		if type(settings.scriptKey) == "string" and #settings.scriptKey > 0 and globals.script_key == nil then
			globals.script_key = settings.scriptKey
			Sanitize.addSecret(settings.scriptKey)
		end

		Roblox.__setHookEnv(globals)

		do
			local orders = Fidelity.ORDERS or {}
			for libName, keys in pairs(orders) do
				local lib = globals[libName]
				if type(lib) == "table" then

					for _, key in ipairs(keys) do
						if lib[key] == nil then
							lib[key] = nil
						end
					end
					Fidelity.markOrdered(lib, keys)
				end
			end

			if globals.script ~= nil then
				Fidelity.markOrdered(globals.script, { "script" })
			end
		end

		if globals.string and type(globals.string.char) == "function" then
			local realChar = globals.string.char
			globals.string.char = Deobfuscation.hookStringChar(
				realChar, trace, nest,
				function(decrypted: string, args: { any })
					if decryptedStringCount < 5000 then
						decryptedStringCount += 1
						decryptedStrings[decryptedStringCount] = decrypted
					end
				end
			)
		end
		if globals.bit32 and type(globals.bit32.bxor) == "function" then
			local realBxor = globals.bit32.bxor
			globals.bit32.bxor = Deobfuscation.hookBit32Bxor(
				realBxor, trace, nest,
				function(a: number, b: number, result: number)
					if bxorLogCount < 64 then
						bxorLogCount += 1
						bxorLog[bxorLogCount] = { a, b, result }
					end
				end
			)
		end
		if globals.table and type(globals.table.concat) == "function" then
			local realConcat = globals.table.concat
			globals.table.concat = Deobfuscation.hookTableConcat(
				realConcat, trace, nest,
				function(assembled: string)
					if decryptedStringCount < 5000 then
						decryptedStringCount += 1
						decryptedStrings[decryptedStringCount] = assembled
					end
				end
			)
		end
		if globals.string and type(globals.string) == "table" then
			Deobfuscation.hookStringLib(globals.string, function(assembled: string, via: string)
				if decryptedStringCount < 5000 then
					decryptedStringCount += 1
					decryptedStrings[decryptedStringCount] = "\1ASSEMBLED\1" .. assembled
				end
			end)
		end

		local builtinsSnapshot = globals.__builtinsSnapshot
		if builtinsSnapshot then
			for _, value in pairs(globals) do
				if type(value) == "function" then
					builtinsSnapshot[value] = true
				end
			end
			globals.__builtinsSnapshot = nil
		end

		for _, blocked in ipairs({ "io", "process", "fs" }) do
			globals[blocked] = nil
		end

		local hiddenKeys: { [string]: any } = {}
		local hiddenNames = {
			"getgenv", "getrenv",
			"hookfunction", "hookfunc", "replaceclosure",
			"getreg", "getregistry",
		}
		for _, name in ipairs(hiddenNames) do
			if globals[name] ~= nil then
				hiddenKeys[name] = globals[name]
				globals[name] = nil
			end
		end
		if next(hiddenKeys) then

			setmetatable(globals, {
				__index = hiddenKeys,
				__newindex = function(_t: any, key: any, value: any)
					rawset(hiddenKeys, key, value)
				end,
			})
		end

		local realFromString = globals.buffer.fromstring
		globals.buffer.fromstring = function(data: any): any
			if opCheck() then
				abort()
			end
			local text = Spy.unwrap(data)
			if type(text) == "string" and #text >= 256 then
				stages[#stages + 1] = {
					nest = nest,
					source = "",
					origin = "buffer",
					executed = true,
					data = string.sub(text, 1, MAX_BUFFER_STAGE_BYTES),
				}
				emitProgress(true)
			end
			return realFromString(text)
		end				local function capture(...: any): any
					if select("#", ...) == 0 then
						error("missing argument #1 to 'loadstring' (string expected)", 0)
					end
				local chunk, chunkName = ...
				if opCheck() then
					abort()
				end
				local text = Spy.unwrap(chunk)

				if type(text) == "function" then
					local pieces: { string } = {}
					local total = 0
					local firstErr: any = nil
					for _ = 1, 1000000 do
						local okPiece, piece = pcall(text)
						if not okPiece then
							if #pieces == 0 then firstErr = piece end
							break
						end
						if piece == nil then break end
						piece = Spy.unwrap(piece)
						if type(piece) ~= "string" or #piece == 0 then break end
						total += #piece
						if total > 33554432 then break end
						pieces[#pieces + 1] = piece
					end
					text = table.concat(pieces)
				end
				if type(text) ~= "string" then
					return nil, "chunk is not a string"
				end

				if #text == 0 then

					local proxy: any
					local noopMt = { __index = function(_t, _k: any)
						return function(_self, ...)
							return proxy
						end
					end }
					proxy = setmetatable({}, noopMt)
					return function()
						return proxy
					end
				end

				local runText = text

				local replacement = nil
				if stagePatch then
					replacement = stagePatch[#text]

					if not replacement then
						local only = stagePatch[-1]
						if only ~= nil then
							replacement = only
							trace:push("note", "stage substituted by fallback (no length match; " .. tostring(#text) .. " bytes)", nest)
						end
					end
				end
				if replacement then
					runText = replacement
					trace:push("note", "stage substituted (patched, " .. tostring(#text) .. " -> " .. tostring(#replacement) .. " bytes)", nest)
				elseif isL(text) then
					local patched = pd(text)
					if patched ~= text then
						runText = patched
					end
				end

				if #text <= 512 then

					local probe = Instrument.lowerBitwise(text) or text
					local ok = pcall(function()
						luau.load(probe)
					end)
					if not ok then

						return nil, "syntax error: malformed chunk"
					end
				end

		local isDuplicate = false
		if type(text) == "string" then
			for _, existing in ipairs(stages) do
				if type(existing) == "table"
					and existing.origin == "loadstring"
					and existing.source == text
				then
					isDuplicate = true
					break
				end
			end
		end

		trace:push("loadstring", text, nest, {
			length = #text,
			origin = "loadstring",
			looksLikeSource = looksLikeSource(text),
			duplicate = isDuplicate,
		})

		if isDuplicate then

			local originalStage = (function()
				for _, s in ipairs(stages) do
					if type(s) == "table"
						and s.origin == "loadstring"
						and s.source == text
					then
						return s
					end
				end
				return nil
			end)()
			return function(...)
				if opCheck() then
					abort()
				end
				emitProgress(true)
				if originalStage then
					originalStage.executed = true
				end

				startClock = os.clock()
				exhausted = false
				exhaustedReason = nil
				local results = table.pack(execute(text, nest + 1, "loadstring", envOverride, nil, ...))
				local ok = results[1]
				if not ok then
					trace:push("note", "nested stage failed: " .. se(results[2]), nest + 1)
					if results[2] ~= nil then
						error(results[2], 0)
					end
					return nil
				end
				return table.unpack(results, 2, results.n)
			end
		end

		local stage: Stage = {
			nest = nest + 1,
			source = text,
			origin = "loadstring",
			executed = false,
		}
		if #stages >= 512 then
			trace:push("note", "stage limit reached (512) - this one was captured but will not run", nest)
			return function()
				if opCheck() then
					abort()
				end
				return nil
			end
		end
		stages[#stages + 1] = stage
			emitProgress(true)

			local fn
			fn = function(...)
				if opCheck() then
					abort()
				end
				emitProgress(true)
				stage.executed = true

				if type(programDir) == "string" and #programDir > 0 then
					for i = 1, select("#", ...) do
						local a = select(i, ...)
						if type(a) == "string"
							and #a >= 1024
							and #a <= MAX_BUFFER_STAGE_BYTES
							and #a > #argProgram then
							argProgram = a
						end
					end
				end
				local envOverride = setfenvMap[fn]

					startClock = os.clock()
					exhausted = false
					exhaustedReason = nil
					local results = table.pack(execute(runText, nest + 1, "loadstring", envOverride, nil, ...))
					local ok = results[1]
					if not ok then
						trace:push("note", "nested stage failed: " .. se(results[2]), nest + 1)

						if results[2] ~= nil then
							error(results[2], 0)
						end
						return nil
					end
					return table.unpack(results, 2, results.n)
			end
			return fn
		end

		globals.loadstring = capture

		globals.load = function(...: any): any
			return (capture :: any)(...)
		end
		Fidelity.register(globals.loadstring, "loadstring")
		Fidelity.register(globals.load, "load")

		globals.loadfile = function(path: any): any
			local name = tostring(Spy.unwrap(path) or "")
			local contents = globals.readfile(name)
			if type(contents) ~= "string" or contents == "" then
				return nil, "no such file"
			end
			trace:push("call", string.format("loadfile(%s)", Serializer.stringLiteral(name)), nest, { file = name })
			return capture(contents)
		end
		globals.dofile = function(path: any): any
			local fn = globals.loadfile(path)
			if type(fn) == "function" then
				return fn()
			end
			return nil
		end

		local softNil: any = nil
		softNil = setmetatable({}, {
			__index = function(_self: any, _k: any): any
				return softNil
			end,
			__call = function(_self: any, ...: any): any
				return nil
			end,
			__add = function(_a: any, _b: any): any return 0 end,
			__sub = function(_a: any, _b: any): any return 0 end,
			__mul = function(_a: any, _b: any): any return 0 end,
			__div = function(_a: any, _b: any): any return 1 end,
			__mod = function(_a: any, _b: any): any return 0 end,
			__pow = function(_a: any, _b: any): any return 1 end,
			__unm = function(_a: any): any return 0 end,
			__concat = function(_a: any, _b: any): any return "" end,
			__eq = function(_a: any, _b: any): any

				if rawequal(_a, _b) then return true end
				if _b == nil or rawequal(_b, softNil) then return true end
				if rawequal(_a, softNil) then return true end
				return false
			end,
			__lt = function(_a: any, _b: any): any return false end,
			__le = function(_a: any, _b: any): any return true end,
			__tostring = function(_self: any): any return "nil" end,
			__len = function(_self: any): any return 0 end,
		})
		globals["__FUHD_SAFE__"] = function(v: any): any
			if v == nil then
				return softNil
			end
			if type(v) == "function" then
				local okW, w = pcall(globals.__wrapFunc, v)
				if okW and w ~= nil then return w end
			end
			return v
		end

		local ssPrinted: { [string]: number } = {}
		local function ssd(kind: string, k: any, v: any)
			ssDiagTotals.events += 1
			ssDiagTotals[kind] = (ssDiagTotals[kind] :: number) + 1
			local c = (ssPrinted[kind] :: number?) or 0
			if c < 3 then
				ssPrinted[kind] = c + 1

			end
		end

		globals["__FUHD_SAFE_SET__"] = function(a: any, k: any, v: any): any
			if a == nil or rawequal(a, softNil) then
				ssd("dropBase", k, v)
				return v
			end
			if rawequal(k, softNil) then
				ssd("softKey", k, v)
			elseif k == nil then
				ssd("nilKey", k, v)
			elseif v == nil and type(k) == "number" and k >= 0 and k < 1000 then
				ssd("nilVal", k, v)
			end
			;(a :: any)[k] = v
			return v
		end

		globals["__FUHD_SAFE_INDEX__"] = function(a: any, k: any): any
			if a == nil or rawequal(a, softNil) then
				return softNil
			end
			if type(a) == "function" then
				if type(k) == "string" then
					return globals.__wrapFunc(function(): any return nil end)
				end
				return nil
			end

			if type(a) == "table" then
				local mt = getmetatable(a)
				if mt == nil then
					return a[k]
				end
			end

			local ok, res = pcall(function(): any return (a :: any)[k] end)
			if ok then
				return res
			end

			if softInstanceCall then
				return softNil
			end

			error(res, 0)
		end

		do
			local bufLib = globals.buffer
			if type(bufLib) == "table" then
				local function isSoft(v: any): boolean
					return type(v) == "table" and rawequal(v, softNil)
				end
				local function coerce(v: any): any
					return if isSoft(v) then 0 else v
				end
				for _, name in ipairs({
					"create", "writeu8", "writeu16", "writeu32", "writei8", "writei16",
					"writei32", "writef32", "writef64", "writeu64",
					"readu8", "readu16", "readu32", "readi8", "readi16", "readi32",
					"readf32", "readf64", "readu64", "copy", "fill",
				}) do
					local real = bufLib[name]
					if type(real) == "function" then
						bufLib[name] = function(a: any, b: any, c: any, d: any, e: any): any
							return real(coerce(a), coerce(b), coerce(c), coerce(d), coerce(e))
						end
					end
				end
			end

			local realType = type
			globals.type = function(v: any): string
				if type(v) == "table" and rawequal(v, softNil) then
					return "nil"
				end
				return realType(v)
			end
		end

		globals[Instrument.CHECK_NAME] = function()
			if exhausted then
				error(BUDGET_ERROR)
			end
			opCount += 1
			if opCount % 256 == 0 then
				if os.clock() - startClock > timeout then
					exhausted = true
					exhaustedReason = "time budget exceeded"
					error(BUDGET_ERROR)
				end
				emitProgress(false)
			end
		end

		globals[Instrument.LOCAL_NAME] = function(name: any, value: any)
			if opCheck() then
				abort()
			end

			if type(value) == "function" and globals.__wrapFunc ~= nil then
				local okW, wrapped = pcall(globals.__wrapFunc, value)
				if okW and wrapped ~= nil then
					value = wrapped
				end
			end
			local key = tostring(name)
			trace:push("newindex", key .. " = " .. (resolveEnvName(value) or Spy.pathOf(value)), nest, {

				key = key,

				valueId = Spy.renderIdOf(value),
			})

			if value ~= nil then

				if type(value) ~= "number" or value == value then
					valueNames[value] = key
					Spy.rename(value, key)
				end
			end
			return value
		end

		globals[Instrument.OP_NAME] = function(op: any, left: any, right: any): any
			local leftInternal = Spy.internalOf(left)
			local rightInternal = Spy.internalOf(right)

			if leftInternal == nil and rightInternal == nil then

				if not PrngTrace.containsAny(left, right) then
					if op == "eq" then
						return left == right
					elseif op == "ne" then
						return left ~= right
					elseif op == "lt" then
						return left < right
					elseif op == "le" then
						return left <= right
					elseif op == "gt" then
						return left > right
					elseif op == "ge" then
						return left >= right
					end
					return false
				end
			end

			if opCheck() then
				abort()
			end

			local leftValue = if leftInternal
				then (if leftInternal.hasConcrete then leftInternal.concrete else nil)
				else left
			local rightValue = if rightInternal
				then (if rightInternal.hasConcrete then rightInternal.concrete else nil)
				else right
			local leftKnown = leftInternal == nil or leftInternal.hasConcrete
			local rightKnown = rightInternal == nil or rightInternal.hasConcrete

			local result: boolean
			local invented = false
			if leftKnown and rightKnown then

				local ok, res = pcall(function()
					if op == "eq" then
						return leftValue == rightValue
					elseif op == "ne" then
						return leftValue ~= rightValue
					elseif op == "lt" then
						return leftValue < rightValue
					elseif op == "le" then
						return leftValue <= rightValue
					elseif op == "gt" then
						return leftValue > rightValue
					elseif op == "ge" then
						return leftValue >= rightValue
					end
					return false
				end)
				if ok then
					result = res == true
				else

					result = if op == "ne" then left ~= right else left == right
					invented = true
				end
			elseif
				(op == "eq" or op == "ne")
				and leftInternal ~= nil
				and rightInternal ~= nil
			then

				local same = left == right
				result = if op == "eq" then same else not same
			else

				if op == "eq" then
					result = false
				elseif op == "ne" then
					result = true
				else
					result = true
				end
				invented = true
			end

			if not invented and PrngTrace.containsAny(leftValue, rightValue, left, right) then
				invented = true
			end

			if invented then
				unknownOpCounter += 1
			end

			trace:push("op", string.format(
				"%s %s %s",
				Spy.pathOf(left),
				OP_SYMBOLS[op] or tostring(op),
				Spy.pathOf(right)
			), nest, {
				op = tostring(op),
				outcome = result,

				concrete = not invented,
			})

			return result
		end

		globals[Instrument.BRANCH_NAME] = function(_id: any, condText: any, kind: any, cond: any, stmt: any)
			if opCheck() then
				abort()
			end
			branchCounter += 1

			local sawInventedOp = unknownOpCounter > lastBranchOpCounter
			lastBranchOpCounter = unknownOpCounter
			local internal = Spy.internalOf(cond)
			local concrete = true
			local outcome: boolean
			if internal then
				concrete = internal.hasConcrete
				if internal.hasConcrete then
					outcome = internal.concrete ~= nil and internal.concrete ~= false
				else

					outcome = true
				end
			else
				outcome = cond ~= nil and cond ~= false
			end
			if sawInventedOp then
				concrete = false
			end
			local source = tostring(condText)
			local kw = if tostring(kind) == "elseif" then "elseif" elseif tostring(kind) == "else" then "else" else "if"

			local opens = (stmt == 1 or stmt == true) and kw ~= "else"
			local forced = forcedBranches and forcedBranches[branchCounter]

			local srcId = tonumber(_id)
			if forced ~= nil then
				trace:push("branch", source, nest, {
					branch = branchCounter,
					srcId = srcId,
					outcome = forced,
					concrete = concrete,
					forced = true,
					kind = kw,
					opens = opens,
				})
				return forced
			end
			trace:push("branch", source, nest, {
				branch = branchCounter,
				srcId = srcId,
				outcome = outcome,
				concrete = concrete,
				kind = kw,
				opens = opens,
			})
			return cond
		end

		globals[Instrument.BRANCH_END_NAME] = function()
			if opCheck() then
				abort()
			end
			trace:push("branch_end", "", nest, {})
		end

		globals[Instrument.ARG_NAME] = function(name: any, value: any)
			if opCheck() then
				abort()
			end

			if Spy.internalOf(value) then
				return value
			end
			return Spy.new(tostring(name), config, value, value ~= nil, 0)
		end

		local envTable

		local lastEnvVia = "_G"

		local pendingEnvVia: string?

		local PROTECTED_GLOBALS: { [string]: boolean } = {
			getfenv = true, setfenv = true, getgenv = true, getrenv = true,
			print = true, warn = true,
			game = true, workspace = true, script = true, shared = true,
			loadstring = true, load = true, require = true,
			Instance = true, Enum = true, task = true,
			type = true, typeof = true, pcall = true, _G = true,
		}

		local LUNE_BLOCKLIST: { [string]: boolean } = {
			vector = true,
			LUNE_VERSION = true,
			lune = true,
		}

		local genvMirror: any

		local envMirror: any

		envTable = setmetatable({}, {
			__index = function(_, key)
				if type(key) == "string" and LUNE_BLOCKLIST[key] then
					return nil
				end
				local known = globals[key]
				if known ~= nil then
					return known
				end

				noteUndefined(key)
				return nil
			end,
			__newindex = function(_, key, value)

				if type(key) == "string" and string.sub(key, 1, 12) == "__glassluau_" then
					pendingEnvVia = nil
					rawset(envTable, key, value)
					return
				end
				local via = pendingEnvVia
				pendingEnvVia = nil
				trace:push("newindex", tostring(key) .. " = " .. (resolveGlobalName(value) or resolveEnvName(value) or Spy.pathOf(value)), nest, {
					global = true,
					key = tostring(key),
					envVia = via,
				})

				globals[key] = value

				globals[key] = value

				if type(key) == "string" then
					if genvMirror ~= nil then
						rawset(genvMirror, key, value)
					end
					if envMirror ~= nil then
						rawset(envMirror, key, value)
					end
				end

				if via == "getgenv" and value ~= nil then
					sharedGetgenvGlobals[key] = value
				end

				if value ~= nil then

					if type(value) ~= "number" or value == value then
						valueNames[value] = tostring(key)
					end
				end
			end,
			__metatable = "The metatable is locked",
		})

		local function makeEnvProxy(): any
			local envBacking: { [any]: any } = {}
			for k, v in pairs(globals) do
				if type(k) == "string" and v ~= nil then
					envBacking[k] = v
				end
			end
			envMirror = envBacking
			return setmetatable(envBacking, {

				__index = function(_, key)
					if type(key) ~= "string" then
						return globals[key]
					end
					local value = globals[key]
					if value ~= nil then
						if opCheck() then
							abort()
						end
						trace:push("index", key, nest, {
							base = "<env>",
							key = key,
							global = true,
							envVia = lastEnvVia,
						})
					else
						noteUndefined(key)
					end
					return value
				end,
				__newindex = function(self, key, value)
					pendingEnvVia = lastEnvVia
					envTable[key] = value

					rawset(self, key, value)
				end,

				__iter = function()
					return pairs(globals)
				end,
				__pairs = function()
					return pairs(globals)
				end,

				__len = function()
					local n = 0
					for _ in pairs(globals) do
						n += 1
					end
					return n
				end,
				__metatable = "The metatable is locked",
			})
		end
		local envProxy = makeEnvProxy()

		if not sharedGenvProxy then
			sharedGenvProxy = envProxy
		end
		local envProxyGlobal = sharedGenvProxy

		local envRecorded = false
		local function envAccess(name: string, proxy: any): any
			lastEnvVia = name

			Symbol.tag(proxy, { kind = "env", expression = name .. "()" })
			if not envRecorded then
				envRecorded = true
				if opCheck() then
					abort()
				end
				trace:push("call", name .. "()", nest, { callee = name, arguments = "", argumentCount = 0 })
			end
			return proxy
		end

		local function argTypeName(value: any): string
			local typeofFn = globals.typeof
			if type(typeofFn) == "function" then
				local ok, name = pcall(typeofFn, value)
				if ok and type(name) == "string" and name ~= "" then
					return name
				end
			end
			return type(value)
		end

		globals.getfenv = function(level: any): any
			if type(level) == "number" then
				if level ~= level or level < 0 then
					error("invalid argument #1 to 'getfenv' (level must be non-negative)", 0)
				end
			elseif level ~= nil and type(level) ~= "function" then
				error("invalid argument #1 to 'getfenv' (number or function expected, got "
					.. argTypeName(level) .. ")", 0)
			end

			local target: any = nil
			if type(level) == "function" then
				target = level
			elseif type(level) ~= "number" then

				local descriptor = Symbol.get(level)
				local original = descriptor and descriptor.detail and descriptor.detail.original
				if type(original) == "function" then
					target = original
				end
			else

				local wanted = if level == nil then 1 else level
				if type(wanted) == "number" and wanted >= 1 then
					target = resolveScriptLevel(wanted)
				end
			end
			if target ~= nil then
				local override = setfenvMap[target]
				if override == nil then
					local okEnv, real = pcall(realGetfenv, target)
					if okEnv and scriptEnvs[real] then
						override = real
					end
				end
				if override ~= nil then
					lastEnvVia = "getfenv"
					return override
				end
			end
			return envAccess("getfenv", envProxyGlobal)
		end
		globals.setfenv = function(target: any, replacement: any): any
			if replacement == nil then
				error("missing argument #2 to 'setfenv' (table expected)", 0)
			elseif type(replacement) ~= "table" then
				error("invalid argument #2 to 'setfenv' (table expected, got "
					.. argTypeName(replacement) .. ")", 0)
			end

			if type(target) ~= "function" then
				local descriptor = Symbol.get(target)
				local original = descriptor and descriptor.detail and descriptor.detail.original
				if type(original) == "function" then
					target = original
				end
			end
			if type(target) == "function" then

				if type(builtinsSnapshot) == "table" and builtinsSnapshot[target] then
					error("unable to setfenv non-Lua closure", 0)
				end
				setfenvMap[target] = replacement
				applyScriptFenv(target, replacement)
			elseif type(target) == "number" then

				local frame = resolveScriptLevel(target)
				if frame ~= nil then
					setfenvMap[frame] = replacement
					applyScriptFenv(frame, replacement)
				end
			end

			return target
		end

		Fidelity.register(globals.getfenv, "getfenv")
		Fidelity.register(globals.setfenv, "setfenv")
		globals._VERSION = "Luau"

		local genvBacking: { [any]: any } = {}
		for k, v in pairs(globals) do
			if type(k) == "string" and v ~= nil then
				genvBacking[k] = v
			end
		end
		local genvProxy = setmetatable(genvBacking, {
			__index = function(_, key)

				if type(key) == "string" then

					if key == "Key" or key == "POLSEC_KEY" or key == "PolSecKey" or key == "FulcrumKey" or key == "API_KEY" then
						local shared = sharedGetgenvGlobals[key]
						if shared == nil then
							return "PolSecBypass_1234567890_FulcrumKey_OK"
						end
						return shared
					end
					local shared = sharedGetgenvGlobals[key]
					local value = if shared ~= nil then shared else globals[key]
					if value ~= nil and opCheck() == false then
						trace:push("index", key, nest, {
							base = "<env>",
							key = key,
							global = true,
							envVia = "_G",
						})
					end
					return value
				end
				return globals[key]
			end,
			__newindex = function(self, key, value)
				if type(key) == "string" and PROTECTED_GLOBALS[key] then
					trace:push("newindex", tostring(key) .. " = " .. Spy.pathOf(value), nest, {
						global = true,
						key = tostring(key),
						envVia = "_G",
					})
					return
				end
				trace:push("newindex", tostring(key) .. " = " .. (resolveGlobalName(value) or resolveEnvName(value) or Spy.pathOf(value)), nest, {
					global = true,
					key = tostring(key),
					envVia = "_G",
				})
				sharedGetgenvGlobals[key] = value

				rawset(self, key, value)
			end,
			__metatable = "The metatable is locked",
		})

		globals._G = genvProxy
		globals.shared = {}

		globals.getgenv = function(): any
			return envAccess("getgenv", genvProxy)
		end

		genvMirror = genvBacking

		globals.getrenv = function(): any
			return envAccess("getrenv", envProxyGlobal)
		end

		globals["__glassluau_vm_trace"] = function(I: any, _p: any, _y: any, L: any, O: any, V: any, f: any, e: any): any
			local n = #vmTrace + 1
			if n <= VM_TRACE_MAX then
				vmTrace[n] = { op = I or "?", chain = _p, a = L, b = O, c = V, d = f, e = e }
			elseif I ~= nil and I ~= "?" and not vmTraceCapped then

				vmTrace[n] = { op = I, chain = _p, a = L, b = O, c = V, d = f, e = e }
			elseif not vmTraceCapped then
				vmTraceCapped = true
			end
			if n % 4096 == 0 then
				emitProgress(true)
			end
			if n % 256 == 0 and opCheck() then
				abort()
			end
			return nil
		end

		globals["__glassluau_buf"] = buffer
		globals["__glassluau_tbl"] = table

		globals["__glassluau_vec"] = if type(vector) == "table" then vector else nil
		rawset(envProxy, "__glassluau_buf", buffer)
		rawset(envProxy, "__glassluau_tbl", table)
		rawset(envProxy, "__glassluau_vec", globals["__glassluau_vec"])
		rawset(envTable, "__glassluau_buf", buffer)
		rawset(envTable, "__glassluau_tbl", table)
		rawset(envTable, "__glassluau_vec", globals["__glassluau_vec"])

		local vmGuardCount = 0
		globals["__glassluau_vm_guard"] = function(): any
			vmGuardCount += 1
			if vmGuardCount % 256 == 0 and opCheck() then
				abort()
			end
			return nil
		end

		globals["__LPH_REG_TRACE__"] = globals["__glassluau_vm_trace"]
		globals["__LPH_REG_GUARD__"] = globals["__glassluau_vm_guard"]

		local luraphStrSeen: { [string]: boolean } = {}
		local luraphStrCount = 0
		globals["__LPH_STR_TRACE__"] = function(value: any): any
			if type(value) == "string" and #value >= 2 then
				if not luraphStrSeen[value] then
					luraphStrSeen[value] = true
					luraphStrCount += 1
					if luraphStrCount <= 5000 then
						decryptedStrings[luraphStrCount] = value
						decryptedStringCount = luraphStrCount
					end
				end
			end
			return value
		end

		globals["__LPH_REG_READ__"] = function(value: any): any
			if type(value) == "string" and #value >= 3 then
				if not luraphStrSeen[value] then
					luraphStrSeen[value] = true
					luraphStrCount += 1
					if luraphStrCount <= 5000 then
						decryptedStrings[luraphStrCount] = value
						decryptedStringCount = luraphStrCount
					end
				end
			end
			return nil
		end

		globals["__LPH_BUF__"] = buffer
		globals["__LPH_VEC__"] = if type(vector) == "table" then vector else nil

		local realRawget = globals.rawget
		local rawgetBlockedKeys: { [string]: boolean } = {}
		for _, name in ipairs(hiddenNames) do
			rawgetBlockedKeys[name] = true
		end
		globals.rawget = function(...: any): any
			local total = select("#", ...)
			if total == 0 then
				return realRawget()
			elseif total == 1 then
				return realRawget((...))
			end
			local tbl, key = ...
			local unwrapped = Spy.unwrap(tbl)

			if unwrapped == envProxy or tbl == envProxy then
				if rawgetBlockedKeys[key] then
					return nil
				end
				return globals[key]
			end
			if unwrapped == nil then
				unwrapped = tbl
			end
			return realRawget(unwrapped, key)
		end

		local realRawset = globals.rawset
		globals.rawset = function(...: any): any
			local total = select("#", ...)
			if total < 3 then
				return (realRawset :: any)(...)
			end
			local tbl, key, value = ...
			local unwrapped = Spy.unwrap(tbl)
			if tbl == genvProxy or unwrapped == genvProxy
				or tbl == envProxy or unwrapped == envProxy then
				sharedGetgenvGlobals[key] = value
			end
			return (realRawset :: any)(...)
		end

		local realGetmetatable = globals.getmetatable
		globals.getmetatable = function(...: any): any
			if select("#", ...) == 0 then
				error("missing argument #1", 0)
			end
			local target = ...
			local unwrapped = Spy.unwrap(target)
			if unwrapped == envProxy or target == envProxy then
				return nil
			end
			return realGetmetatable(target)
		end

		local function fixErrorMsg(msg: string): string
			if type(msg) ~= "string" then return msg end

			msg = string.gsub(msg, "attempt to perform arithmetic %((%w+)%) on (%w+) and (%w+)", "attempt to perform arithmetic on a %2 value")

			msg = string.gsub(msg, "%[string \"[^\"]*\"%]:(%d+):", function(line)
				return '[string ""]:'
			end)
			return msg
		end
		local realPcall = pcall
		globals.pcall = function(fn: any, ...: any): (boolean, ...any)
			local results = table.pack(realPcall(fn, ...))
			if not results[1] then
				results[2] = fixErrorMsg(tostring(results[2]))
			end
			return table.unpack(results, 1, results.n)
		end
		local realXpcall = xpcall
		globals.xpcall = function(fn: any, handler: any, ...: any): (boolean, ...any)
			local wrappedHandler = function(err: any)
				return handler(fixErrorMsg(tostring(err)))
			end
			local results = table.pack(realXpcall(fn, wrappedHandler, ...))
			return table.unpack(results, 1, results.n)
		end

		local realPairs = globals.pairs
		globals.pairs = function(t: any): ()
			local unwrapped = Spy.unwrap(t)
			if unwrapped == envProxy or t == envProxy then
				return next, globals, nil
			end
			return realPairs(t)
		end

		do
			local skip = {
				type = true,
				rawget = true,
				rawset = true,
				rawequal = true,
				rawlen = true,
				getmetatable = true,
				setmetatable = true,
				next = true,
				pairs = true,
				ipairs = true,
				gethui = true,
				__wrapFunc = true,
				__glassluau_vm_trace = true,
				__glassluau_vm_guard = true,
				__LPH_STR_TRACE__ = true,
				__LPH_REG_READ__ = true,
				__LPH_REG_TRACE__ = true,
				__LPH_REG_GUARD__ = true,
			}
			local pairsFn = globals.pairs or pairs
			local names = {}
			for key, value in pairsFn(globals) do
				if type(key) == "string" and not skip[key] and type(value) == "function" then
					names[#names + 1] = key
				end
			end
			for _, name in ipairs(names) do
				local fn = globals[name]

				local dualNil: any
				dualNil = setmetatable({}, {
					__call = function(): any return nil end,
					__index = function(): any return dualNil end,
					__iter = function(): any
						return function(): any return nil end
					end,
				})
				local dualFn: any = setmetatable({}, {
					__call = function(_self, ...: any): any
						return (fn :: any)(...)
					end,
					__index = function(_self, key: any): any
						if type(key) == "string" then
							return dualNil
						end
						return nil
					end,
					__iter = function()
						return function()
							return nil
						end
					end,
				})
				Symbol.tag(dualFn, {
					kind = "closure",
					expression = name,
					typeName = "function",
					detail = { dualNature = true, callable = true, aliasOf = name },
				})
				globals[name] = dualFn
			end

			for _, libName in ipairs({
				"string", "table", "math", "bit32", "coroutine", "utf8", "buffer",
			}) do
				local lib = globals[libName]
				if type(lib) == "table" then
					for key, value in pairsFn(lib) do
						if type(key) == "string" and type(value) == "function" then
							local member = value
							local dualMember: any = setmetatable({}, {
								__call = function(_self, ...: any): any
									return (member :: any)(...)
								end,
								__index = function(_self, mkey: any): any
									if mkey == "FindFirstChild" or mkey == "FindFirstChildOfClass"
										or mkey == "FindFirstChildWhichIsA" or mkey == "WaitForChild"
										or mkey == "GetService" or mkey == "GetChildren"
										or mkey == "GetDescendants" then
										return function(): any
											return nil
										end
									end
									return nil
								end,
							})
							Symbol.tag(dualMember, {
								kind = "closure",
								expression = libName .. "." .. key,
								typeName = "function",
								detail = { dualNature = true, callable = true, aliasOf = key },
							})
							lib[key] = dualMember
						end
					end
				end
			end
		end

		do
			local function registerTree(tbl: any, depth: number)
				if depth > 2 or type(tbl) ~= "table" then
					return
				end
				for key, value in pairs(tbl) do
					if type(key) ~= "string" then
						continue
					end
					if type(value) == "function" then
						Fidelity.register(value, key)
					elseif type(value) == "table" and depth < 2 and Symbol.get(value) == nil then
						registerTree(value, depth + 1)
					end
				end
			end
			local function registerContainer(container: any)
				if type(container) ~= "table" then
					return
				end
				local key, value = next(container)
				while key ~= nil do
					if type(key) == "string" then
						if type(value) == "function" then
							Fidelity.register(value, key)
						elseif type(value) == "table" and Symbol.get(value) == nil then
							registerTree(value, 1)
						end
					end
					key, value = next(container, key)
				end
			end
			registerContainer(globals)

			local globalsMt = getmetatable(globals)
			if type(globalsMt) == "table" then
				registerContainer(rawget(globalsMt, "__index"))
			end
			registerContainer(sharedGetgenvGlobals)
		end

		for _, name in ipairs({
			"string", "table", "math", "debug", "bit32",
			"coroutine", "utf8", "buffer", "os", "task",
		}) do
			local lib = globals[name]
			if type(lib) == "table" and not table.isfrozen(lib) then
				pcall(table.freeze, lib)
			end
		end

		return envTable
	end

		softInstanceCall = settings.softInstanceCall
			or source:find("moonveil", 1, true) ~= nil
			or source:find("MoonVeil", 1, true) ~= nil
			or source:find(":ta(", 1, true) ~= nil
			or (source:sub(1, 8) == "return({" and source:find("}:M(", 1, true) ~= nil)

			or (source:sub(1, 8) == "return({" and isL(source))

		do
			local okLX, LuraphExtract = pcall(require, "./luraph_extract")
			if okLX and LuraphExtract and type(LuraphExtract.extractEmbeddedChunks) == "function" then
				local okChunks, chunks = pcall(LuraphExtract.extractEmbeddedChunks, source, 400)
				if okChunks and type(chunks) == "table" then
					local added = 0
					for _, chunk in ipairs(chunks) do
						if added >= 8 then
							break
						end

						local keep = false
						if LuraphExtract.isLuraphSource(chunk) then
							keep = true
						else
							local okLoad = pcall(luau.load, chunk, { debugName = "staticpeel" })
							if okLoad and #chunk >= 800 then
								keep = true
							end
						end
						if keep then
							stages[#stages + 1] = {
								source = chunk,
								origin = "static",
								executed = false,
							}
							added += 1
							trace:push("note", "static peel: embedded chunk " .. #chunk .. " bytes", 0)
						end
					end
				end
			end
		end

		local isMoonVeil = isM(source)
		local isFulcrum = isF(source)
		local isLuraph = isL(source)
		local runSource = source
		local function compilesEntry(text: string): boolean
			local okT, fnT = pcall(luau.load, text, { debugName = "entrycheck" })
			return okT and fnT ~= nil
		end
		if isFulcrum then
			local patched = pf(source)
			if patched ~= source and (settings.noVmPatch ~= true or not compilesEntry(runSource)) and compilesEntry(patched) then
				runSource = patched
				trace:push("note", "Fulcrum VM detected - patching dispatch loops for tracing", 0)
			end
		elseif isMoonVeil and settings.noVmPatch ~= true then
			local patched = pm(source)
			if patched ~= source and compilesEntry(patched) then
				runSource = patched
				trace:push("note", "MoonVeil VM detected - patching dispatch loops for tracing", 0)
			else
				trace:push("note", "MoonVeil entry patch rejected: result does not compile or disabled", 0)
			end
		elseif isLuraph and settings.noVmPatch ~= true then
			trace:push("note", "Luraph entry detected - attempting dispatch patch", 0)
			local patched = pd(source)
			if patched ~= source then
				local okEx, LuraphExtract = pcall(require, "./luraph_extract")
				if okEx and LuraphExtract then
					local withStr = LuraphExtract.patchByteConcat(patched)
					if withStr ~= patched then
						patched = withStr
					end
				end
				if compilesEntry(patched) then
					runSource = patched
					trace:push("note", "Luraph VM detected - patching dispatch loops for tracing", 0)
				else
					trace:push("note", "Luraph entry patch rejected: result does not compile", 0)
				end
			else
				trace:push("note", "Luraph entry: no dispatcher match (loader/table shell - will patch after stage peel)", 0)
			end
		end

		local ok, err, entryReturn = execute(runSource, 0, "entry")
		emitProgress(true)
		entryKind = type(entryReturn)

		if ok and type(entryReturn) == "function" then

			trace:push("note", "entry returned a function - invoking it", 0)
			local fnOk, fnErr = pcall(entryReturn)
			if not fnOk and fnErr then
				trace:push("note", "entry function: " .. se(fnErr), 0)
			end
			emitProgress(true)
		elseif ok and type(entryReturn) == "table" then
			local hasCallable = false
			for _, v in pairs(entryReturn) do
				if type(v) == "function" then
					hasCallable = true
					break
				end
			end
			if hasCallable then
				trace:push("note", "returned function table detected - invoking all entries", 0)
				for key, fn in pairs(entryReturn) do
					if type(fn) == "function" then

						local fnOk, fnErr = pcall(fn)
						if not fnOk and fnErr then
							trace:push("note", "returned function " .. tostring(key) .. ": " .. se(fnErr), 0)
						end
					end
				end
				emitProgress(true)
			end
		end

		do
			local staticRan = 0
			for _, stage in ipairs(stages) do
				if type(stage) ~= "table" or stage.origin ~= "static" or stage.executed then
					continue
				end
				local chunk = stage.source
				if type(chunk) ~= "string" or #chunk == 0 then
					continue
				end
				if overBudget() then
					break
				end

				local okLoad = pcall(luau.load, chunk, { debugName = "staticstage" })
				if not okLoad then
					continue
				end
				stage.executed = true
				staticRan += 1
				trace:push("note", "static stage: executing peeled chunk (" .. #chunk .. " bytes)", 1)
				startClock = os.clock()
				exhausted = false
				exhaustedReason = nil
				execute(chunk, 1, "static", nil, nil)
				emitProgress(true)
				if staticRan >= 4 then
					break
				end
			end
		end

		local vmSource: string? = nil
		local isMoonVeilStage = false
		local programBytes: string? = nil
		for _, stage in ipairs(stages) do
			if type(stage) ~= "table" then
				continue
			end
			if type(stage.origin) == "string" and stage.origin == "buffer"
				and type(stage.data) == "string" then
				programBytes = stage.data
			end
			if type(stage.origin) == "string"
				and (stage.origin == "loadstring" or stage.origin == "static")
				and type(stage.source) == "string" then
				if isL(stage.source) then
					vmSource = stage.source
				elseif isM(stage.source) then
					vmSource = stage.source
					isMoonVeilStage = true
				elseif isF(stage.source) then
					vmSource = stage.source
					isMoonVeilStage = false
				end
			end
		end

if type(programDir) == "string" and #programDir > 0 then
				if #argProgram > #programBytes then
					programBytes = argProgram
				end
				if type(vmSource) == "string" and #vmSource > 0 then
					local vp = programDir .. "/vm.lua"
					if pcall(fs.writeFile, vp, vmSource) then
						programFiles[#programFiles + 1] = vp
					end
				end
				if type(programBytes) == "string" and #programBytes > 0 then
					local pp = programDir .. "/prog.bin"
					if pcall(fs.writeFile, pp, programBytes) then
						programFiles[#programFiles + 1] = pp
					end
				end
			end

		if #vmTrace == 0 then
			if vmSource and programBytes and #programBytes < MAX_BUFFER_STAGE_BYTES then
				local patchedVm
				if isMoonVeilStage then
					patchedVm = pm(vmSource)
				elseif isF(vmSource) then
					patchedVm = pf(vmSource)
				else
					patchedVm = pd(vmSource)
				end

				exhausted = false
				exhaustedReason = nil
				startClock = os.clock()
				trace:push("note", "VM re-run: executing recovered VM with " .. tostring(#programBytes) .. "-byte program", 1)
				local okVm, vmErr = execute(patchedVm, 1, "loadstring", nil, buffer.fromstring(programBytes))

				if okVm then
					local programFn = vmErr
					if type(programFn) == "function" then
						for i = #vmTrace, 1, -1 do
							vmTrace[i] = nil
						end
						vmTraceCapped = false
						trace:push("note", "VM re-run: invoking recovered program", 1)

						local progOk, progErr = pcall(programFn)
						if progOk then
							programVerdict = "returned " .. type(progErr)
						else
							programVerdict = "error: " .. se(progErr)
						end
						trace:push("note", "VM re-run: program " .. programVerdict, 1)
					else
						programVerdict = "stage returned " .. type(programFn) .. ", not a function"
						trace:push("note", "VM re-run: " .. programVerdict, 1)
					end
				elseif not vmTraceCapped then
					programVerdict = "VM error: " .. se(vmErr)
					trace:push("note", "VM re-run: " .. programVerdict, 1)
				end
			end
		end

		do
			local okEnv, StdlibMod = pcall(require, "../env/stdlib")
			if okEnv and StdlibMod and StdlibMod.envCallLog then
				local okLog, logText = pcall(StdlibMod.envCallLog)
				if okLog and type(logText) == "string" and #logText > 0 then
					if #logText > 6000 then
						logText = "..." .. string.sub(logText, #logText - 6000)
					end
					finalEnvCalls = logText
					trace:push("note", "final env calls: " .. logText, 1)
				end

				local okFirst, firstText = pcall(StdlibMod.envCallFirst)
				if okFirst and type(firstText) == "string" and #firstText > 0 then
					firstEnvCalls = firstText
				end
			end
		end

		local extractedStringTable: { [string]: string } = {}
		for _, stage in ipairs(stages) do
			if type(stage) == "table" and type(stage.source) == "string" then
				for hex, value in pairs(Deobfuscation.extractStringTableFromSource(stage.source)) do
					extractedStringTable[hex] = value
				end
			end
		end

		for hex, value in pairs(Deobfuscation.extractStringTable(trace)) do
			extractedStringTable[hex] = value
		end

		local LuraphExtract = require("./luraph_extract")
		for _, stage in ipairs(stages) do
			if type(stage) == "table" and type(stage.source) == "string"
				and LuraphExtract.isLuraphSource(stage.source) then
				for key, value in pairs(LuraphExtract.extractKTable(stage.source)) do
					extractedStringTable[key] = value
				end
			end
		end

		local unrolledSource: string? = nil
		if Deobfuscation.shouldUnroll(stages) then
			local parts: { string } = {}
			for i, stage in ipairs(stages) do
				if type(stage) == "table" and stage.source and stage.source ~= "" then
					parts[#parts + 1] = "-- Stage " .. i .. " (" .. (stage.origin or "unknown") .. ")"
					parts[#parts + 1] = stage.source
					parts[#parts + 1] = ""
				end
			end
			if #parts > 0 then
				unrolledSource = table.concat(parts, "\n")
			end
		end

		if exhausted and isL(source) then
			local recovered = false
			for _, stg in ipairs(stages) do
				if type(stg) == "table" and stg.executed
					and type(stg.source) == "string" and #stg.source > 0 then
					recovered = true
					break
				end
			end
			local budgetOnly = exhaustedReason == "time budget exceeded"
				or (type(err) == "string" and err:find("budget", 1, true) ~= nil)
			if recovered and budgetOnly then
				exhausted = false
				exhaustedReason = nil
				err = nil
				ok = true
				trace:push("note", "luraph: stages recovered; long-running script stopped at time budget", 0)
			end
		end

		return {
			trace = trace,
			stages = stages,
			outputs = outputs,
			outputsDropped = outputsDropped,
			outputTotalBytes = outputTotalBytes,
			ok = ok,
			err = if ok or exhausted then nil else se(err),
			exhausted = exhausted,
			exhaustedReason = exhaustedReason,
			vmTrace = vmTrace,
			vmTraceCapped = vmTraceCapped,
			antiNilIssues = antiNil.issues,
			undefinedGlobals = undefinedList(),
			nilCulprit = nilCulprit,
			ssDiag = ssDiagTotals,

			decryptedStrings = decryptedStrings,
			decryptedStringCount = decryptedStringCount,
			stringTable = extractedStringTable,
			unrolledSource = unrolledSource,
			bxorLog = bxorLog,
		}
	end

	local primary = runOnce(nil)
	local explored: { any } = {}
	if not primary.exhausted then
		local candidates: { any } = {}

		for iRecord, record in ipairs(primary.trace.records) do
			local detail = record.detail

			if record.kind == "branch" and detail and not detail.forced
				and (detail.opens ~= false or detail.kind == "elseif") then

				local score = 0
				if detail.concrete == false then
					score = 10
				end

				score += math.max(0, 100 - iRecord // 100)
				candidates[#candidates + 1] = { record = record, score = score }
			end
		end

		table.sort(candidates, function(a, b) return a.score > b.score end)
		local maxExplored = settings.maxExplored or 3
		for _, candidate in ipairs(candidates) do
			if #explored >= maxExplored then
				break
			end
			local branchRecord = candidate.record
			local forced = not branchRecord.detail.outcome
			local alt = runOnce({ [branchRecord.detail.branch] = forced })
			if not alt.exhausted then
				explored[#explored + 1] = {
					branch = branchRecord.detail.branch,
					cond = branchRecord.expression,
					taken = branchRecord.detail.outcome,
					forced = forced,
					trace = alt.trace,
				}
			end
		end
	end

	Stdlib.setBudgetHook(nil)

	local result: Result = {
		trace = primary.trace,
		stages = primary.stages,
		outputs = primary.outputs,
		outputsDropped = primary.outputsDropped,
		outputTotalBytes = primary.outputTotalBytes,
		ok = primary.ok,
		err = primary.err,
		exhausted = primary.exhausted,
		exhaustedReason = primary.exhaustedReason,
		explored = explored,
		vmTrace = primary.vmTrace,
		vmTraceCapped = primary.vmTraceCapped,
		undefinedGlobals = primary.undefinedGlobals,
		nilCulprit = primary.nilCulprit,
		ssDiag = primary.ssDiag,

		decryptedStrings = primary.decryptedStrings,
		decryptedStringCount = primary.decryptedStringCount,
		programFiles = programFiles,
		programVerdict = programVerdict,
		finalEnvCalls = finalEnvCalls,
		firstEnvCalls = firstEnvCalls,
		entryKind = entryKind,
		stringTable = primary.stringTable,
		unrolledSource = primary.unrolledSource,
	}
	return result
end

return Sandbox
