local luau = require("@lune/luau")

local Serializer = require("../core/serializer")
local Spy = require("../core/spy")
local Symbol = require("../core/symbol")

local realDebugGetinfo = debug.getinfo

local realNewproxy = newproxy

local Stdlib = {}

local chunkSources: { [string]: string } = {}
Stdlib.chunkSources = chunkSources

local bytecodeCache: { [string]: string } = {}

local liftedSet = setmetatable({}, { __mode = "k" })

local __stats: { [string]: number } = {}
Stdlib.__stats = __stats

local __firstCall: { [any]: string } = {}
Stdlib.__firstCall = __firstCall
local budgetHook: (() -> boolean)? = nil
local budgetTick = 0
local budgetDead = false

function Stdlib.setBudgetHook(hook: (() -> boolean)?)
	budgetHook = hook
	budgetTick = 0
	budgetDead = false
end

local function budgetSample()
	if budgetHook ~= nil then
		if budgetHook() then
			if not budgetDead then
				local rows = {}
				for k, v in pairs(__stats) do rows[#rows + 1] = { k, v } end
				table.sort(rows, function(a, b) return a[2] > b[2] end)
				print("STATPROBE top library calls at overrun:")
				for i = 1, math.min(#rows, 22) do print("   " .. rows[i][1] .. " = " .. tostring(rows[i][2])) end
			end
			budgetDead = true
			error("sandbox budget exceeded")
		end
	end
end

local function unwrapArg(value: any): any
	local kind = type(value)
	if kind == "table" or kind == "userdata" or kind == "function" then
		return Spy.unwrap(value)
	end
	return value
end

local function lifted<T...>(fn: (...any) -> T...): (...any) -> T...
	local wrapper = function(...)
		if budgetHook ~= nil then
			budgetTick += 1
			if budgetDead or budgetTick % 2048 == 0 then
				budgetSample()
			end
		end
		local count = select("#", ...)

		if count == 0 then
			return fn()
		elseif count == 1 then
			local a = ...
			local ua = unwrapArg(a)
			if ua == a then
				return fn(...)
			end
			return fn(ua)
		elseif count == 2 then
			local a, b = ...
			local ua, ub = unwrapArg(a), unwrapArg(b)
			if ua == a and ub == b then
				return fn(...)
			end
			return fn(ua, ub)
		elseif count == 3 then
			local a, b, c = ...
			local ua, ub, uc = unwrapArg(a), unwrapArg(b), unwrapArg(c)
			if ua == a and ub == b and uc == c then
				return fn(...)
			end
			return fn(ua, ub, uc)
		end
		local args = table.create(count)
		local changed = false
		for i = 1, count do
			local value = select(i, ...)
			local unwrapped = Spy.unwrap(value)
			args[i] = unwrapped
			if unwrapped ~= value then
				changed = true
			end
		end
		if not changed then
			return fn(...)
		end
		return fn(table.unpack(args, 1, count))
	end
	liftedSet[wrapper] = true
	return wrapper
end

Stdlib.lifted = lifted

Stdlib.liftedSet = liftedSet

local ENV_CALL_RING: { string } = {}
local ENV_CALL_HEAD = 0
local ENV_CALL_TOTAL = 0
local ENV_CALL_RING_CAP = 240
local function recordEnvCall(label: string, args: { string }, results: string)
	ENV_CALL_TOTAL += 1
	local line = string.format("#%d %s(%s) -> %s", ENV_CALL_TOTAL, label, table.concat(args, ", "), results)
	ENV_CALL_HEAD += 1
	if ENV_CALL_HEAD > ENV_CALL_RING_CAP then
		ENV_CALL_HEAD = 1
	end
	ENV_CALL_RING[ENV_CALL_HEAD] = line
end

local function argRepr(value: any): string
	local t = type(value)
	if t == "string" then

		local head = if #value > 64 then string.sub(value, 1, 64) else value
		local flat = head:gsub("[^%w%p ]", "?")
		if #value > 64 then
			flat = flat .. "...(" .. tostring(#value) .. "b)"
		elseif #flat > 40 then
			flat = string.sub(flat, 1, 37) .. "..."
		end
		return string.format("s%q", flat)
	end
	if t == "number" then
		return string.format("n%.6g", value)
	end
	if t == "table" then
		return "table{" .. tostring(rawlen and rawlen(value) or #value) .. "}"
	end
	return t
end

local function resultRepr(values: { any }, n: number): string
	local parts: { string } = {}
	for i = 1, math.min(n, 3) do
		parts[#parts + 1] = argRepr(values[i])
	end
	return table.concat(parts, ", ")
end

function Stdlib.envCallFirst(): string

	local seen: { [string]: boolean } = {}
	local parts: { string } = {}
	for i = 1, #__firstCall do
		local label = __firstCall[i]
		if not seen[label] then
			seen[label] = true
			parts[#parts + 1] = (__firstCall[label] or label) .. "  [" .. tostring(__stats[label] or 0) .. "x]"
		end
	end
	return table.concat(parts, " ; ")
end

function Stdlib.envCallLog(): string
	local parts: { string } = {}
	for i = 1, ENV_CALL_RING_CAP do
		local line = ENV_CALL_RING[(ENV_CALL_HEAD + i - 1) % ENV_CALL_RING_CAP + 1]
		if line then
			parts[#parts + 1] = line
		end
	end
	return "last " .. tostring(#parts) .. "/" .. tostring(ENV_CALL_TOTAL) .. " env calls: " .. table.concat(parts, " ; ")
end

local function liftLibrary(source: { [string]: any }, libname: string?): { [string]: any }
	local out = {}
	for key, value in pairs(source) do
		if type(value) == "function" then
			local inner = lifted(value)
			local label = (libname or "?") .. "." .. tostring(key)

			local HOT_CALLS = 2000
			out[key] = function(...)
				local n = (__stats[label] or 0) + 1
				__stats[label] = n
				if n > HOT_CALLS then
					return inner(...)
				end

				local shouldLog = (n % 64) == 1
				local results
				if shouldLog then
					local argTypes: { string } = {}
					for i = 1, select("#", ...) do
						argTypes[#argTypes + 1] = argRepr((select(i, ...)))
						if #argTypes >= 4 then
							break
						end
					end
results = table.pack(inner(...))

				if __firstCall[label] == nil then
					local at = table.concat(argTypes, ", ")
					__firstCall[label] = (#argTypes > 0) and (label .. "(" .. at .. ")")
						or (label .. "()")
					__firstCall[#__firstCall + 1] = label
				end
				recordEnvCall(label, argTypes, resultRepr(results, results.n))
					return table.unpack(results, 1, results.n)
				end
				return inner(...)
			end
		else
			out[key] = value
		end
	end
	return out
end

local function buildString(): { [string]: any }
	local out = liftLibrary(string, "string")

	local realRep = string.rep
	out.rep = lifted(function(...: any): string
		local total = select("#", ...)
		if total == 0 then
			return realRep()
		elseif total == 1 then
			local text = ...
			return realRep(text)
		end
		local text, count, separator = ...
		if type(count) ~= "number" or count ~= count then
			return realRep(text)
		end
		local capped = math.min(math.max(math.floor(count), 0), 1000000)
		if total == 2 then
			return realRep(tostring(text), capped)
		end
		return realRep(tostring(text), capped, separator)
	end)

	out.dump = function(fn: any): string
		local unwrapped = Spy.unwrap(fn)
		if type(unwrapped) ~= "function" then
			error("bad argument #1 to 'dump' (function expected, got " .. type(fn) .. ")")
		end

		if liftedSet[unwrapped] then
			error("bad argument #1 to 'dump' (function expected, got C function)")
		end

		local okSrc, src = pcall(debug.info, unwrapped, "s")
		if okSrc and type(src) == "string" then
			local text = chunkSources[src]
			if text then
				local cached = bytecodeCache[text]
				if cached then
					return cached
				end
				local okBC, bc = pcall(luau.compile, text)
				if okBC and type(bc) == "string" and #bc > 0 then
					bytecodeCache[text] = bc
					return bc
				end
			end
		end

		error("unable to dump given function")
	end

	return out
end

local function buildTable(trace: any?, nest: number?): { [string]: any }
	local out = liftLibrary(table, "table")

	local realCreate = table.create
	out.create = lifted(function(...: any): { any }
		if select("#", ...) == 0 then
			return (realCreate :: any)()
		end
		local count, value = ...
		if type(count) ~= "number" or count ~= count then
			return realCreate(count)
		end
		return realCreate(math.min(math.max(math.floor(count), 0), 1000000), value)
	end)

	out.insert = lifted(table.insert)

	local realConcat = table.concat
	out.concat = function(...: any): string
		local total = select("#", ...)
		if total == 0 then
			return realConcat()
		end
		local t, sep, i, j = ...
		if total == 1 then
			return realConcat(Spy.unwrap(t) or t)
		elseif total == 2 then
			return realConcat(Spy.unwrap(t) or t, Spy.unwrap(sep))
		elseif total == 3 then
			return realConcat(Spy.unwrap(t) or t, Spy.unwrap(sep), Spy.unwrap(i))
		end
		return realConcat(Spy.unwrap(t) or t, Spy.unwrap(sep), Spy.unwrap(i), Spy.unwrap(j))
	end

	return out
end

local function buildMath(): { [string]: any }
	local out = liftLibrary(math, "math")

	local Fidelity = require("./fidelity")
	local ghi: { hi: number, lo: number, primed: boolean } = { hi = 0, lo = 0, primed = false }

	local function gNext32(): number
		if not ghi.primed then

			ghi.hi, ghi.lo = Fidelity.pcgSeed(0x5eed)
			ghi.primed = true
		end
		local o = Fidelity.pcgNext32(ghi.hi, ghi.lo)
		ghi.hi, ghi.lo = Fidelity.pcgStep(ghi.hi, ghi.lo)
		return o
	end

	out.random = lifted(function(...: any): any
		local given = select("#", ...)
		local low, high = ...
		if given == 0 then

			local rl = gNext32()
			local rh = gNext32()
			return (rl + rh * 4294967296) * 5.421010862427522e-20
		elseif given == 1 then

			if type(low) ~= "number" then
				error("invalid argument #1 to 'random' (number expected, got " .. typeof(low) .. ")", 2)
			end
			local u = math.floor(low)
			if u < 1 then
				error("bad argument #1 to 'random' (interval is empty)", 2)
			end
			local o = gNext32()
			local a0 = u % 65536
			local a1 = math.floor(u / 65536)
			local b0 = o % 65536
			local b1 = math.floor(o / 65536)
			local ll = a0 * b0
			local mid = a1 * b0 + a0 * b1 + math.floor(ll / 65536)
			local hh = a1 * b1 + math.floor(mid / 65536)
			return 1 + (hh % 4294967296)
		elseif given == 2 then

			if type(low) ~= "number" or low % 1 ~= 0 then
				error("invalid argument #1 to 'random' (number has no integer representation)", 2)
			end
			if type(high) ~= "number" or high % 1 ~= 0 then
				error("invalid argument #2 to 'random' (number has no integer representation)", 2)
			end
			local l = low
			local u = high
			if u < l then
				error("bad argument #2 to 'random' (interval is empty)", 2)
			end
			local span = bit32.band(u - l, 0xFFFFFFFF)
			local o = gNext32()
			local a0 = (span + 1) % 65536
			local a1 = math.floor((span + 1) / 65536)
			local b0 = o % 65536
			local b1 = math.floor(o / 65536)
			local ll = a0 * b0
			local mid = a1 * b0 + a0 * b1 + math.floor(ll / 65536)
			local hh = a1 * b1 + math.floor(mid / 65536)
			return l + (hh % 4294967296)
		else
			error("wrong number of arguments", 2)
		end
	end)

	out.randomseed = lifted(function(value: number?)
		if type(value) ~= "number" then
			error("invalid argument #1 to 'randomseed' (number expected, got " .. typeof(value) .. ")", 2)
		end
		local s = math.floor(value)
		ghi.hi, ghi.lo = Fidelity.pcgSeed(s)
		ghi.primed = true
	end)

	if out.nan == nil then
		out.nan = 0 / 0
	end

	if out.e == nil then
		out.e = 2.718281828459045
	end
	if out.tau == nil then
		out.tau = 6.283185307179586
	end
	if out.phi == nil then
		out.phi = 1.618033988749895
	end
	if out.sqrt2 == nil then
		out.sqrt2 = 1.4142135623730951
	end

	return out
end

local function readClock(clock: { elapsed: number, drift: number? }): number
	local drift = (clock.drift or 0) + 1e-6
	clock.drift = drift
	return clock.elapsed + drift
end

local function buildOs(freezeTime: number, clock: { elapsed: number, drift: number? }, _onHostile: ((message: string) -> ())?): { [string]: any }

	local real: { [string]: any } = {
		time = function(): number

			return math.floor(freezeTime + clock.elapsed)
		end,
		clock = function(): number
			return readClock(clock)
		end,
		date = lifted(function(format: string?, when: number?): any
			local realDate = os.date
			local ok, result = pcall(realDate, format or "%c", when or freezeTime)
			if ok then
				return result
			end
			return ""
		end),
		difftime = lifted(function(a: number, b: number): number
			return (tonumber(a) or 0) - (tonumber(b) or 0)
		end),
	}

	local HOSTILE_OS: { [string]: boolean } = {
		execute = true,
		exit = true,
		getenv = true,
		remove = true,
		rename = true,
		setlocale = true,
		tmpname = true,
	}

	return setmetatable(real, {
		__index = function(_: any, key: any): any
			if HOSTILE_OS[tostring(key)] then
				return nil
			end
			return nil
		end,
		__metatable = "The metatable is locked",
	})
end

local function typeNameOf(value: any): string
	local tagged = Symbol.typeName(value)
	if type(tagged) == "string" and tagged ~= "" then
		return tagged
	end
	local unwrapped = Spy.unwrap(value)
	if unwrapped ~= nil then
		return type(unwrapped)
	end
	return type(value)
end

Stdlib.typeNameOf = typeNameOf

local function buildCoroutine(checkBudget: (() -> boolean)?, trace: any?, nest: number?): { [string]: any }

	local out = liftLibrary(coroutine, "coroutine")
	local realResume = coroutine.resume
	out.resume = function(...: any): any
		if select("#", ...) == 0 then
			error("missing argument #1 to 'resume' (thread expected)", 0)
		end
		return realResume(...)
	end
	out.wrap = function(...: any): any
		if select("#", ...) == 0 then
			error("missing argument #1 to 'wrap' (function expected)", 0)
		end
		local fn = ...
		local target = Spy.unwrap(fn)
		if type(target) ~= "function" then
			return function() end
		end

		local co = coroutine.create(target)
		return function(...: any)
			if checkBudget and checkBudget() then
				error("sandbox budget exceeded")
			end

			local results = table.pack(coroutine.resume(co, ...))
			if not results[1] then
				error(results[2], 0)
			end
			return table.unpack(results, 2, results.n)
		end
	end
	out.create = function(...: any): any
		if select("#", ...) == 0 then
			error("missing argument #1 to 'create' (function expected)", 0)
		end
		local fn = ...
		local target = Spy.unwrap(fn)
		if type(target) ~= "function" then
			target = function() end
		end

		if checkBudget then
			local wrappedTarget = function(...: any)
				if checkBudget() then
					error("sandbox budget exceeded")
				end
				return target(...)
			end
			return coroutine.create(wrappedTarget)
		end
		return coroutine.create(target)
	end
	return out
end

local function buildTask(record: ((expression: string, callee: string, renderedArgs: string, argCount: number) -> ())?, clock: { elapsed: number, drift: number? }, taskState: any): { [string]: any }

	local pending: { any } = {}

	local function recordCall(name: string, fn: any, extra: { any }, extraCount: number): string
		local parts: { string } = { Serializer.value(fn) }
		for i = 1, extraCount do
			parts[#parts + 1] = Serializer.value(extra[i])
		end
		local rendered = table.concat(parts, ", ")
		if record then
			record("task." .. name .. "(" .. rendered .. ")", "task." .. name, rendered, 1 + extraCount)
		end
		return rendered
	end

	local function drain()
		while true do
			local nextItem = nil
			local nextIndex = 0
			for i = 1, #pending do
				local item = pending[i]
				if item.canceled then
					table.remove(pending, i)
					nextItem = nil
					nextIndex = 0
					break
				elseif item.at <= clock.elapsed then
					nextItem = item
					nextIndex = i
					break
				end
			end
			if not nextItem then
				return
			end
			table.remove(pending, nextIndex)
			coroutine.resume(nextItem.thread, table.unpack(nextItem.args, 1, nextItem.count))
		end
	end

	local function queue(name: string, at: number, fn: any, ...): any
		local count = select("#", ...)
		local extra = table.create(count)
		for i = 1, count do
			extra[i] = select(i, ...)
		end
		recordCall(name, fn, extra, count)
		local target = Spy.unwrap(fn)
		if type(target) ~= "function" then
			return nil
		end
		local thread = coroutine.create(target)
		pending[#pending + 1] = {
			thread = thread,
			args = extra,
			count = count,
			at = at,
			canceled = false,
		}
		return thread
	end

	return {
		wait = function(duration: any?): number
			if duration ~= nil and type(Spy.unwrap(duration) or duration) ~= "number" then
				error("invalid argument #1 to 'wait' (number expected, got "
					.. typeNameOf(duration) .. ")", 2)
			end
			local value = tonumber(Spy.unwrap(duration)) or 0
			if record then
				record("task.wait(" .. Serializer.value(value) .. ")", "task.wait", Serializer.value(value), 1)
			end

			local waited = if value > 0 then value else 1 / 60
			clock.elapsed = clock.elapsed + waited

			pcall(function()
				local SignalMod = require("./signal")
				SignalMod.fireFrame(waited)
			end)

			drain()
			if taskState then
				taskState.resumeSpawned()

				if taskState.isSpawned(coroutine.running()) then
					coroutine.yield()
				end
			end
			return waited
		end,
		spawn = function(fn: any, ...): any

			if fn == nil then
				error("invalid argument #1 to 'spawn' (function or thread expected)", 2)
			end
			local count = select("#", ...)
			local extra = table.create(count)
			for i = 1, count do
				extra[i] = select(i, ...)
			end
			recordCall("spawn", fn, extra, count)
			local target = Spy.unwrap(fn)
			if type(target) ~= "function" then
				return nil
			end

			local thread = coroutine.create(target)

			if taskState then
				taskState.add(thread)
			end
				pcall(coroutine.resume, thread, table.unpack(extra, 1, count))
				return thread
		end,
		defer = function(fn: any, ...): any

			if fn == nil then
				error("invalid argument #1 to 'defer' (function or thread expected)", 2)
			end
			return queue("defer", clock.elapsed, fn, ...)
		end,
		delay = function(duration: any, fn: any, ...): any

			if fn == nil then
				error("invalid argument #2 to 'delay' (function or thread expected)", 2)
			end
			if duration == nil or type(Spy.unwrap(duration) or duration) ~= "number" then
				error("invalid argument #1 to 'delay' (number expected, got "
					.. typeNameOf(duration) .. ")", 2)
			end
			local value = tonumber(Spy.unwrap(duration)) or 0
			return queue("delay", clock.elapsed + value, fn, ...)
		end,
		desynchronize = function() end,
		synchronize = function() end,
		cancel = function(thread: any): any
			if thread == nil then
				error("missing argument #1 to 'cancel' (thread expected)", 2)
			end
			if type(thread) == "thread" then
				for i = 1, #pending do
					if pending[i].thread == thread then
						pending[i].canceled = true
					end
				end
				if taskState then
					taskState.remove(thread)
				end
				pcall(coroutine.close, thread)
			end
			return nil
		end,
	}
end

export type Options = {

	freezeTime: number?,

	clock: { elapsed: number, drift: number? }?,

	zlib: any?,

	onHostile: ((message: string) -> ())?,

	trace: any?,

	nest: number?,

	taskState: any?,

	envProxy: any?,
}

function Stdlib.build(options: Options?): { [string]: any }
	local settings = options or {}
	local freezeTime = settings.freezeTime or 1700000000
	local clock = settings.clock or { elapsed = 0 }

	local globals: { [string]: any } = {}

	globals.string = buildString()
	globals.table = buildTable(settings.trace, settings.nest)
	globals.math = buildMath()
	globals.os = buildOs(freezeTime, clock, settings.onHostile)
	globals.coroutine = buildCoroutine(settings.checkBudget, settings.trace, settings.nest)
	globals.task = buildTask(if settings.trace then function(expression: string, callee: string, renderedArgs: string, argCount: number)
		if settings.trace and settings.trace.records then
			settings.trace:push("call", expression, settings.nest or 0, {
				callee = callee,
				arguments = renderedArgs,
				argumentCount = argCount,
			})
		end
	end else nil, clock, settings.taskState)
	globals.bit32 = liftLibrary(bit32, "bit32")
	globals.utf8 = liftLibrary(utf8, "utf8")

	local function isCombiningMark(cp: number): boolean
		return (cp >= 0x0300 and cp <= 0x036F)
			or (cp >= 0x1AB0 and cp <= 0x1AFF)
			or (cp >= 0x1DC0 and cp <= 0x1DFF)
			or (cp >= 0x20D0 and cp <= 0x20FF)
			or (cp >= 0xFE20 and cp <= 0xFE2F)
	end

	local S_BASE, L_BASE, V_BASE, T_BASE = 0xAC00, 0x1100, 0x1161, 0x11A7
	local L_COUNT, V_COUNT, T_COUNT = 19, 21, 28
	local N_COUNT = V_COUNT * T_COUNT
	local S_COUNT = L_COUNT * N_COUNT

	local function isHangulSyllable(cp: number): boolean
		return cp >= S_BASE and cp < S_BASE + S_COUNT
	end

	local function decomposeHangul(cp: number): { number }
		local index = cp - S_BASE
		local l = L_BASE + index // N_COUNT
		local v = V_BASE + (index % N_COUNT) // T_COUNT
		local t = index % T_COUNT
		if t > 0 then
			return { l, v, T_BASE + t }
		end
		return { l, v }
	end

	local function composeHangul(l: number, v: number): number
		return S_BASE + ((l - L_BASE) * V_COUNT + (v - V_BASE)) * T_COUNT
	end

	local function isHangulLV(cp: number): boolean
		return isHangulSyllable(cp) and (cp - S_BASE) % T_COUNT == 0
	end

	local function isHangulL(cp: number): boolean
		return cp >= L_BASE and cp < L_BASE + L_COUNT
	end

	local function isHangulV(cp: number): boolean
		return cp >= V_BASE and cp < V_BASE + V_COUNT
	end

	local function isHangulT(cp: number): boolean
		return cp > T_BASE and cp < T_BASE + T_COUNT
	end

	local function decomposeString(text: string): { number }
		local cps: { number } = {}
		local i = 1
		local n = #text
		while i <= n do
			local cp = utf8.codepoint(text, i)
			cps[#cps + 1] = cp

			i += if cp < 0x80 then 1 elseif cp < 0x800 then 2 elseif cp < 0x10000 then 3 else 4
		end

		local out: { number } = {}
		local DECOMP: { [number]: { number } } = {
			[0xC0] = { 0x41, 0x300 }, [0xC1] = { 0x41, 0x300 }, [0xC2] = { 0x41, 0x302 },
			[0xC3] = { 0x41, 0x303 }, [0xC4] = { 0x41, 0x308 }, [0xC5] = { 0x41, 0x30A },
			[0xC7] = { 0x43, 0x327 }, [0xC8] = { 0x45, 0x300 }, [0xC9] = { 0x45, 0x301 },
			[0xCA] = { 0x45, 0x302 }, [0xCB] = { 0x45, 0x308 }, [0xCC] = { 0x49, 0x300 },
			[0xCD] = { 0x49, 0x301 }, [0xCE] = { 0x49, 0x302 }, [0xCF] = { 0x49, 0x308 },
			[0xD1] = { 0x4E, 0x303 }, [0xD2] = { 0x4F, 0x300 }, [0xD3] = { 0x4F, 0x301 },
			[0xD4] = { 0x4F, 0x302 }, [0xD5] = { 0x4F, 0x303 }, [0xD6] = { 0x4F, 0x308 },
			[0xD9] = { 0x55, 0x300 }, [0xDA] = { 0x55, 0x301 }, [0xDB] = { 0x55, 0x302 },
			[0xDC] = { 0x55, 0x308 }, [0xDD] = { 0x59, 0x301 }, [0xE0] = { 0x61, 0x300 },
			[0xE1] = { 0x61, 0x301 }, [0xE2] = { 0x61, 0x302 }, [0xE3] = { 0x61, 0x303 },
			[0xE4] = { 0x61, 0x308 }, [0xE5] = { 0x61, 0x30A }, [0xE7] = { 0x63, 0x327 },
			[0xE8] = { 0x65, 0x300 }, [0xE9] = { 0x65, 0x301 }, [0xEA] = { 0x65, 0x302 },
			[0xEB] = { 0x65, 0x308 }, [0xEC] = { 0x69, 0x300 }, [0xED] = { 0x69, 0x301 },
			[0xEE] = { 0x69, 0x302 }, [0xEF] = { 0x69, 0x308 }, [0xF1] = { 0x6E, 0x303 },
			[0xF2] = { 0x6F, 0x300 }, [0xF3] = { 0x6F, 0x301 }, [0xF4] = { 0x6F, 0x302 },
			[0xF5] = { 0x6F, 0x303 }, [0xF6] = { 0x6F, 0x308 }, [0xF9] = { 0x75, 0x300 },
			[0xFA] = { 0x75, 0x301 }, [0xFB] = { 0x75, 0x302 }, [0xFC] = { 0x75, 0x308 },
			[0xFD] = { 0x79, 0x301 }, [0xFF] = { 0x79, 0x308 },
		}
		for _, cp in ipairs(cps) do
			if isHangulSyllable(cp) then

				for _, piece in ipairs(decomposeHangul(cp)) do
					out[#out + 1] = piece
				end
				continue
			end
			local d = DECOMP[cp]
			if d then
				for _, piece in ipairs(d) do
					out[#out + 1] = piece
				end
			else
				out[#out + 1] = cp
			end
		end
		return out
	end

	if not globals.utf8.nfdnormalize then
		globals.utf8.nfdnormalize = function(text: string): string
			local parts: { string } = {}
			for _, cp in ipairs(decomposeString(text)) do
				parts[#parts + 1] = utf8.char(cp)
			end
			return table.concat(parts)
		end
	end

	if not globals.utf8.nfcnormalize then

		globals.utf8.nfcnormalize = function(text: string): string
			local decomposed = decomposeString(text)
			local RECOMP: { [string]: number } = {
				["0x41,0x300"] = 0xC0, ["0x41,0x301"] = 0xC1, ["0x41,0x302"] = 0xC2,
				["0x41,0x303"] = 0xC3, ["0x41,0x308"] = 0xC4, ["0x41,0x30A"] = 0xC5,
				["0x43,0x327"] = 0xC7, ["0x45,0x300"] = 0xC8, ["0x45,0x301"] = 0xC9,
				["0x45,0x302"] = 0xCA, ["0x45,0x308"] = 0xCB, ["0x49,0x300"] = 0xCC,
				["0x49,0x301"] = 0xCD, ["0x49,0x302"] = 0xCE, ["0x49,0x308"] = 0xCF,
				["0x4E,0x303"] = 0xD1, ["0x4F,0x300"] = 0xD2, ["0x4F,0x301"] = 0xD3,
				["0x4F,0x302"] = 0xD4, ["0x4F,0x303"] = 0xD5, ["0x4F,0x308"] = 0xD6,
				["0x55,0x300"] = 0xD9, ["0x55,0x301"] = 0xDA, ["0x55,0x302"] = 0xDB,
				["0x55,0x308"] = 0xDC, ["0x59,0x301"] = 0xDD, ["0x61,0x300"] = 0xE0,
				["0x61,0x301"] = 0xE1, ["0x61,0x302"] = 0xE2, ["0x61,0x303"] = 0xE3,
				["0x61,0x308"] = 0xE4, ["0x61,0x30A"] = 0xE5, ["0x63,0x327"] = 0xE7,
				["0x65,0x300"] = 0xE8, ["0x65,0x301"] = 0xE9, ["0x65,0x302"] = 0xEA,
				["0x65,0x308"] = 0xEB, ["0x69,0x300"] = 0xEC, ["0x69,0x301"] = 0xED,
				["0x69,0x302"] = 0xEE, ["0x69,0x308"] = 0xEF, ["0x6E,0x303"] = 0xF1,
				["0x6F,0x300"] = 0xF2, ["0x6F,0x301"] = 0xF3, ["0x6F,0x302"] = 0xF4,
				["0x6F,0x303"] = 0xF5, ["0x6F,0x308"] = 0xF6, ["0x75,0x300"] = 0xF9,
				["0x75,0x301"] = 0xFA, ["0x75,0x302"] = 0xFB, ["0x75,0x308"] = 0xFC,
				["0x79,0x301"] = 0xFD, ["0x79,0x308"] = 0xFF,
			}
			local out: { number } = {}
			local i = 1
			while i <= #decomposed do
				local cp = decomposed[i]
				local nxt = decomposed[i + 1]
				if nxt ~= nil and isHangulL(cp) and isHangulV(nxt) then

					local composed = composeHangul(cp, nxt)
					local third = decomposed[i + 2]
					if third ~= nil and isHangulT(third) then
						composed += third - T_BASE
						i += 3
					else
						i += 2
					end
					out[#out + 1] = composed
					continue
				elseif nxt ~= nil and isHangulLV(cp) and isHangulT(nxt) then
					out[#out + 1] = cp + (nxt - T_BASE)
					i += 2
					continue
				end
				if nxt ~= nil and isCombiningMark(nxt) then
					local key = string.format("0x%X,0x%X", cp, nxt)
					local merged = RECOMP[key]
					if merged then
						out[#out + 1] = merged
						i += 2
						continue
					end
				end
				out[#out + 1] = cp
				i += 1
			end
			local parts: { string } = {}
			for _, cp in ipairs(out) do
				parts[#parts + 1] = utf8.char(cp)
			end
			return table.concat(parts)
		end
	end

	if not globals.utf8.graphemes then
		globals.utf8.graphemes = function(s: string)
			local len = utf8.len(s)
			if not len then return function() return nil end end
			local pos = 1
			return function()
				if pos > #s then return nil end
				local startPos = pos

				local cp = utf8.codepoint(s, pos)

				if cp < 0x80 then pos += 1
				elseif cp < 0x800 then pos += 2
				elseif cp < 0x10000 then pos += 3
				else pos += 4 end

				while pos <= #s do
					local ncp = utf8.codepoint(s, pos)
					local isCombining = (ncp >= 0x0300 and ncp <= 0x036F)
						or (ncp >= 0xFE20 and ncp <= 0xFE2F)
						or (ncp >= 0x1DC0 and ncp <= 0x1DFF)
						or (ncp >= 0x20D0 and ncp <= 0x20FF)
						or (ncp >= 0xA670 and ncp <= 0xA69F)
						or (ncp >= 0x0488 and ncp <= 0x0489)
						or (ncp >= 0x0D4E and ncp <= 0x0D4E)
					if not isCombining then break end
					if ncp < 0x80 then pos += 1
					elseif ncp < 0x800 then pos += 2
					elseif ncp < 0x10000 then pos += 3
					else pos += 4 end
				end
				return startPos, pos - 1
			end
		end
	end
	globals.buffer = liftLibrary(buffer, "buffer")
	do

		local MAX_BUFFER_BYTES = 16 * 1024 * 1024
		local realBufferCreate = globals.buffer.create
		globals.buffer.create = lifted(function(size: number): any
			if type(size) ~= "number" or size ~= size then
				size = 0
			end
			if size < 0 then
				error("bad buffer size", 2)
			end
			if size > MAX_BUFFER_BYTES then
				error("buffer size exceeds sandbox limit", 2)
			end
			return realBufferCreate(math.floor(size))
		end)
	end

	local realNext = next
	local Fidelity = require("./fidelity")
	globals.next = function(...: any): any

		if select("#", ...) == 0 then
			return realNext()
		end
		local subject, control = ...

		local internal = Spy.internalOf(subject)
		if internal then
			if internal.hasConcrete and type(internal.concrete) == "table" then
				return realNext(internal.concrete, control)
			end
			return nil
		end
		if type(subject) == "userdata" then
			return nil
		end

		if type(subject) == "table" and Fidelity.orderedKeys(subject) ~= nil then
			return Fidelity.next(subject, control)
		end
		return realNext(subject, control)
	end
	globals.pairs = pairs
	globals.ipairs = ipairs

	globals.newproxy = function(withMetatable: any?): any

		return realNewproxy(withMetatable == true)
	end

	globals.select = lifted(select)

	globals.rawget = function(...: any): any
		if select("#", ...) == 0 then
			return rawget()
		end
		local tbl, key = ...
		local unwrapped = Spy.unwrap(tbl)
		if unwrapped == nil then
			unwrapped = tbl
		end
		return rawget(unwrapped, key)
	end
	globals.rawset = function(...: any)
		if select("#", ...) == 0 then
			return rawset()
		end
		local total = select("#", ...)
		local tbl, key, value = ...
		if total < 3 then

			if total < 2 then
				return rawset(Spy.unwrap(tbl) or tbl)
			end
			return rawset(Spy.unwrap(tbl) or tbl, key)
		end
		local unwrapped = Spy.unwrap(tbl)
		if unwrapped == nil then
			unwrapped = tbl
		end
		return rawset(unwrapped, key, value)
	end

	local realRawequal = rawequal
	local realError = error
	globals.rawequal = function(a: any, b: any): boolean
		local ua = Spy.unwrap(a)
		local ub = Spy.unwrap(b)
		if (ua == globals.require and ub == realError)
			or (ua == realError and ub == globals.require)
			or (ua == globals.require and ub == globals.error)
			or (ua == globals.error and ub == globals.require) then
			return true
		end
		return realRawequal(ua, ub)
	end
	globals.rawlen = lifted(rawlen)

	globals.tonumber = function(...: any): number?
		if select("#", ...) == 0 then
			return (tonumber :: any)()
		end
		local value, base = ...
		local raw = Spy.unwrap(value)
		if raw == nil then return nil end
		local rawBase = Spy.unwrap(base)
		if rawBase == nil then

			return (tonumber :: any)(raw)
		end
		return (tonumber :: any)(raw, rawBase)
	end

	local realUnpack = table.unpack
	globals.unpack = function(list: any, i: number?, j: number?): ...any
		local t = Spy.unwrap(list)
		local lo = i or 1
		local hi = j
		if type(t) == "string" then
			if hi == nil then hi = #t end
		elseif type(t) == "table" then
			if hi == nil then hi = #t end
		else
			return
		end

		return realUnpack(t, lo, hi)
	end

	if type(collectgarbage) == "function" then
		local realCollect = collectgarbage

		globals.collectgarbage = function(option: any, ...)
			local opt = tostring(Spy.unwrap(option) or "collect")
			if opt == "collect" or opt == "stop" or opt == "restart" then
				return nil
			end
			local ok, result = pcall(realCollect, opt, ...)
			if ok then
				return result
			end
			error(tostring(result), 2)
		end
	end
	if type(gcinfo) == "function" then
		globals.gcinfo = gcinfo
	end

	globals.require = function()
		return nil
	end

	local addrCounter = 0
	local addrCache: { [any]: string } = setmetatable({}, { __mode = "k" })

	local function datatypeString(v: any): string?
		local target = v
		if Spy.is(v) then
			local inner = Spy.unwrap(v)
			if inner ~= nil then
				target = inner
			end
		end
		local sym = Symbol.get(target)
		if sym == nil or type(sym.typeName) ~= "string" or sym.typeName == "" then
			return nil
		end
		if sym.kind ~= "datatype" then

			return nil
		end
		local expression = sym.expression
		if sym.typeName == "Enum" and type(expression) == "string"
			and string.match(expression, "^Enum%.[%w_]+$") ~= nil then
			return expression
		end
		if type(expression) == "string"
			and (sym.typeName == "Rect" or sym.typeName == "NumberRange") then
			local args = string.match(expression, "^%w+%.new%((.*)%)$")
			if args ~= nil then
				return args
			end
		end
		return sym.typeName
	end

	local function toRobloxString(v: any): string
		local s = tostring(v)
		local prefix, hex = string.match(s, "^(%w+: 0x)(%x+)$")
		if prefix and #hex > 8 then
			local named = datatypeString(v)
			if named ~= nil then
				return named
			end
			local cached = addrCache[v]
			if not cached then
				addrCounter += 1
				local refType = string.match(s, "^(%w+):") or "table"
				cached = string.format("%s: 0x%08x", refType, addrCounter * 0x10000 + 0x10000000)
				addrCache[v] = cached
			end
			return cached
		end

		if s == "Enum" then
			local path = datatypeString(v)
			if path ~= nil then
				return path
			end
		end
		return s
	end
	globals.tostring = function(...: any): string
		if select("#", ...) == 0 then
			return tostring()
		end
		local value = ...
		if Spy.is(value) then
			return toRobloxString(value)
		end
		return toRobloxString(Spy.unwrap(value))
	end

	globals.type = function(...: any): string
		if select("#", ...) == 0 then
			return type()
		end
		local value = ...
		if Spy.is(value) then
			local internal = Spy.internalOf(value)
			if internal and internal.memberName then
				return "function"
			end
			local sym = Symbol.get(value)
			if sym and (sym.kind == "instance" or sym.kind == "service") then
				return "userdata"
			end
			if sym and sym.typeName then
				return sym.typeName
			end
			return "table"
		end
		return type(Spy.unwrap(value))
	end

	globals.setmetatable = function(...: any): any
		if select("#", ...) == 0 then
			return setmetatable()
		end
		local target, meta = ...
		local subject = Spy.unwrap(target)
		if type(subject) ~= "table" then
			return target
		end
		local ok, result = pcall(setmetatable, subject, Spy.unwrap(meta))
		if ok then
			return result
		end
		return subject
	end

	globals.getmetatable = function(target: any): any

		if Spy.is(target) then
			return "The metatable is locked"
		end
		local unwrapped = Spy.unwrap(target)
		local ok, result = pcall(getmetatable, unwrapped)
		if ok and result ~= nil then
			if settings.envProxy and unwrapped == settings.envProxy then
				return nil
			end
			if type(unwrapped) == "table" then
				local mt = getmetatable(unwrapped)
				if type(mt) == "table" and mt.__metatable == "The metatable is locked" then
					return nil
				end
			end
			if result == "The metatable is locked" then
				return "The metatable is locked"
			end
			if type(unwrapped) == "string" then
				return result
			end
			return result
		end
		return nil
	end

	globals.iscclosure = function(f: any): boolean
		if type(f) ~= "function" then return false end
		return liftedSet[f] ~= true
	end
	globals.islclosure = function(f: any): boolean
		if type(f) ~= "function" then return false end
		return liftedSet[f] == true
	end
	globals.checkclosure = globals.iscclosure
	globals.is_executor_closure = globals.iscclosure
	globals.isexecutorclosure = globals.iscclosure
	globals.is_our_closure = globals.iscclosure
	globals.isourclosure = globals.iscclosure

	globals.getexecutorname = function(): string
		return "Lune"
	end
	globals.identifyexecutor = globals.getexecutorname
	globals.getexecutorname = globals.getexecutorname

	globals.checkcaller = function(): boolean
		return true
	end
	globals.isexecutorcall = globals.checkcaller
	globals.is_executor_call = globals.checkcaller

	globals.setclipboard = function(_value: any) end
	globals.setrbxclipboard = globals.setclipboard
	globals.toclipboard = globals.setclipboard
	globals.getclipboard = function(): string
		return ""
	end
	globals.fromclipboard = function(): string
		local f = globals.getclipboard
		if type(f) == "function" then
			local ok, v = pcall(f)
			if ok then return v end
		end
		return ""
	end

	local _identityLevel = 8
	globals.getthreadidentity = function(): number
		return _identityLevel
	end
	globals.getidentity = globals.getthreadidentity
	globals.getthreadcontext = globals.getthreadidentity
	globals.setthreadidentity = function(_level: number) end
	globals.setidentity = globals.setthreadidentity
	globals.setthreadcontext = globals.setthreadidentity

	local hwidChars = "0123456789ABCDEF"
	local hwidParts = {}
	for i = 1, 32 do
		local idx = math.random(1, 16)
		hwidParts[i] = string.sub(hwidChars, idx, idx)
	end
	local _hwid = table.concat(hwidParts)
	globals.gethwid = function(): string
		return _hwid
	end
	globals.get_hwid = globals.gethwid

	globals.getrawmetatable = function(obj: any): any
		local unwrapped = Spy.unwrap(obj)
		if unwrapped == nil then unwrapped = obj end
		local ok, mt = pcall(getmetatable, unwrapped)
		if ok then return mt end
		return nil
	end
	globals.setrawmetatable = function(_obj: any, mt: any): any
		return mt
	end
	globals.getrawmetatable = globals.getrawmetatable

	globals.isfrozen = function(tbl: any): boolean
		local unwrapped = Spy.unwrap(tbl)
		if type(unwrapped) ~= "table" then return false end
		return table.isfrozen(unwrapped)
	end
	globals.isreadonly = globals.isfrozen
	globals.is_readonly = globals.isfrozen

	globals.clonefunction = function(f: any): any
		return f
	end
	globals.clonefunction = globals.clonefunction

	globals.queue_on_teleport = function(_src: any) end
	globals.queueonteleport = globals.queue_on_teleport

	local _namecallMethod: string? = nil
	globals.getnamecallmethod = function(): string?
		return _namecallMethod
	end
	globals.get_namecall_method = globals.getnamecallmethod
	globals.setnamecallmethod = function(_method: any) end
	globals.set_namecallmethod = globals.setnamecallmethod

	globals.Drawing = nil
	globals.drawing = nil

	local b64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	globals.base64encode = function(data: any): string
		data = tostring(Spy.unwrap(data) or "")
		local result = ""
		for i = 1, #data, 3 do
			local a, b, c = string.byte(data, i, i + 2)
			local n = a * 65536 + (b or 0) * 256 + (c or 0)
			result ..= string.sub(b64Chars, math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
			result ..= string.sub(b64Chars, math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
			result ..= (i + 1 <= #data) and string.sub(b64Chars, math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
			result ..= (i + 2 <= #data) and string.sub(b64Chars, n % 64 + 1, n % 64 + 1) or "="
		end
		return result
	end
	globals.base64_encode = globals.base64encode
	globals.b64encode = globals.base64encode
	globals.base64decode = function(data: any): string
		data = tostring(Spy.unwrap(data) or "")
		data = string.gsub(data, "[^" .. b64Chars .. "=]", "")
		local result = ""
		for i = 1, #data, 4 do
			local a = string.find(b64Chars, string.sub(data, i, i)) - 1
			local b = (i + 1 <= #data) and (string.find(b64Chars, string.sub(data, i + 1, i + 1)) - 1) or 0
			local c = (i + 2 <= #data) and (string.find(b64Chars, string.sub(data, i + 2, i + 2)) - 1) or 0
			local d = (i + 3 <= #data) and (string.find(b64Chars, string.sub(data, i + 3, i + 3)) - 1) or 0
			local n = a * 262144 + b * 4096 + c * 64 + d
			result ..= string.char(math.floor(n / 65536) % 256)
			if string.sub(data, i + 2, i + 2) ~= "=" then result ..= string.char(math.floor(n / 256) % 256) end
			if string.sub(data, i + 3, i + 3) ~= "=" then result ..= string.char(n % 256) end
		end
		return result
	end
	globals.base64_decode = globals.base64decode
	globals.b64decode = globals.base64decode

	globals.mouse1press = function() end
	globals.mouse1release = function() end
	globals.mouse1click = function() end
	globals.mouse2press = function() end
	globals.mouse2release = function() end
	globals.mouse2click = function() end
	globals.mousescroll = function() end
	globals.mousemoveabs = function() end
	globals.mousemoverel = function() end
	globals.keypress = function() end
	globals.keyrelease = function() end
	globals.keytap = function() end

	globals.rconsolecreate = function() end
	globals.rconsoleshow = function() end
	globals.rconsolesettitle = function() end
	globals.rconsoleclear = function() end
	globals.rconsoleprint = function() end
	globals.rconsolewarn = function() end
	globals.rconsoleinfo = function() end
	globals.rconsoleerr = function() end
	globals.rconsoleerror = function() end
	globals.rconsoleinput = function() end
	globals.rconsoledebug = function() end
	globals.rconsoledestroy = function() end
	globals.rconsolename = function() end
	globals.consolecreate = globals.rconsolecreate
	globals.consoleshow = globals.rconsoleshow
	globals.consolesettitle = globals.rconsolesettitle
	globals.consoleclear = globals.rconsoleclear
	globals.consoleprint = globals.rconsoleprint
	globals.consolewarn = globals.rconsolewarn
	globals.consoleinfo = globals.rconsoleinfo
	globals.consoleerr = globals.rconsoleerr
	globals.consoleerror = globals.rconsoleerror
	globals.consoleinput = globals.rconsoleinput
	globals.consoledebug = globals.rconsoledebug

	globals.fireclickdetector = function() end
	globals.fireproximityprompt = function() end
	globals.firesignal = function() end
	globals.firetouchinterest = function() end
	globals.enableconnection = function() end
	globals.disableconnection = function() end

	globals.iswindowactive = function(): boolean return true end
	globals.isrbxactive = function(): boolean return true end
	globals.isgameactive = function(): boolean return true end

	globals.getinstances = function(): { any } return {} end
	globals.get_nil_instances = globals.getinstances
	globals.getnilinstances = globals.getinstances
	globals.getobjects = function(): { any } return {} end
	globals.getgc = function(): { any } return {} end
	globals.get_gc_objects = globals.getgc
	globals.getreg = function(): { any } return {} end
	globals.getregistry = globals.getreg
	globals.getrunningscripts = function(): { any } return {} end
	globals.getscripts = globals.getrunningscripts
	globals.getloadedmodules = function(): { any } return {} end
	globals.getconnections = function(): { any } return {} end

	globals.getsenv = function() return nil end
	globals.getmenv = globals.getsenv
	globals.getcallingscript = function() return nil end
	globals.get_calling_script = globals.getcallingscript
	globals.getscriptclosure = function() return nil end
	globals.getscriptfunction = globals.getscriptclosure
	globals.getscriptbytecode = function() return nil end
	globals.getscripthash = function() return nil end
	globals.getfunctionhash = function() return nil end
	globals.gethiddenproperty = function() return nil, nil end
	globals.getrenderproperty = function() return nil end
	globals.getnamecallmethod = function() return nil end
	globals.getstack = function() return nil end
	globals.getproto = function() return nil end
	globals.getprotos = function() return nil end

	return globals
end

return Stdlib
