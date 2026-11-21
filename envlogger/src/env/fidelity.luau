local Symbol = require("../core/symbol")

local Fidelity = {}

local names: { [any]: string } = setmetatable({}, { __mode = "k" })

local cset: { [any]: boolean } = setmetatable({}, { __mode = "k" })

local orders: { [any]: { string } } = setmetatable({}, { __mode = "k" })
local orderIndex: { [any]: { [string]: number } } = setmetatable({}, { __mode = "k" })

function Fidelity.register(fn: any, name: string): any
	if type(fn) == "function" and type(name) == "string" then
		names[fn] = name
		cset[fn] = true
	end
	return fn
end

function Fidelity.cname(fn: any): string?
	return names[fn]
end

function Fidelity.registerTree(tbl: any, depth: number?)
	local limit = depth or 1
	if type(tbl) ~= "table" then
		return
	end
	for key, value in pairs(tbl) do
		if type(key) ~= "string" then
			continue
		end
		if type(value) == "function" then
			names[value] = key
			cset[value] = true
		elseif limit > 1 and type(value) == "table" and Symbol.get(value) == nil then
			Fidelity.registerTree(value, limit - 1)
		end
	end
end

function Fidelity.isC(fn: any): boolean
	if type(fn) ~= "function" then
		return false
	end
	if cset[fn] == true then
		return true
	end
	return false
end

function Fidelity.markOrdered(tbl: any, keys: { string })
	orders[tbl] = keys
	local idx: { [string]: number } = {}
	for i, k in ipairs(keys) do
		idx[k] = i
	end
	orderIndex[tbl] = idx
end

function Fidelity.orderedKeys(tbl: any): { string }?
	return orders[tbl]
end

function Fidelity.next(tbl: any, prev: any): (any, any)
	local keys = orders[tbl]
	if keys == nil then
		return next(tbl, prev)
	end
	if prev == nil then
		local k = keys[1]
		if k == nil then
			return nil
		end
		return k, (tbl :: any)[k]
	end
	local idx = orderIndex[tbl][prev]
	if idx == nil then

		return next(tbl, prev)
	end
	local k = keys[idx + 1]
	if k == nil then

		local seen: { [string]: boolean } = orderIndex[tbl]
		local nxt, val = next(tbl, prev)

		while nxt ~= nil and seen[nxt] ~= nil do
			nxt, val = next(tbl, nxt)
		end
		return nxt, val
	end
	return k, (tbl :: any)[k]
end

function Fidelity.pairs(tbl: any): (...any)
	local ordered = orders[tbl]
	if ordered == nil then
		return pairs(tbl)
	end
	return Fidelity.next, tbl, nil
end

function Fidelity.missing(index: number, suffix: string?): string
	if suffix == nil or suffix == "" then
		return string.format("missing argument #%d", index)
	end
	return string.format("missing argument #%d to '%s'", index, tostring(suffix))
end

function Fidelity.missingTyped(fnName: string, index: number, expected: string): string
	return string.format("missing argument #%d to '%s' (%s expected)", index, fnName, expected)
end

function Fidelity.invalid(fnName: string, index: number, expected: string, got: string): string
	return string.format("invalid argument #%d to '%s' (%s expected, got %s)", index, fnName, expected, got)
end

function Fidelity.dotError(method: string): string
	return string.format("Expected ':' not '.' calling member function %s", method)
end

function Fidelity.typeOf(value: any): string
	local t = type(value)
	if t == "nil" then
		return "nil"
	end
	return t
end

function Fidelity.cwrap(impl: (...any) -> ...any, name: string, opts: { [string]: any }?): (...any) -> ...any
	local minArgs = 0
	local missingMsg: string? = nil
	local validate: ((...any) -> string?)? = nil
	if opts then
		if type(opts.minArgs) == "number" then
			minArgs = opts.minArgs
		end
		if type(opts.missingMsg) == "string" then
			missingMsg = opts.missingMsg
		end
		if type(opts.validate) == "function" then
			validate = opts.validate
		end
	end
	local fn
	fn = function(...: any): ...any
		local n = select("#", ...)
		if n < minArgs then
			if missingMsg then
				error(missingMsg, 2)
			else
				error(string.format("missing argument #1"), 2)
			end
		end
		if validate then
			local err = validate(...)
			if err ~= nil then
				error(err, 2)
			end
		end
		return impl(...)
	end
	Fidelity.register(fn, name)
	return fn
end

local PCG_M_HI = 0x5851F42D
local PCG_M_LO = 0x4C957F2D
local PCG_INC = 105
local TWO32 = 4294967296

local function u16parts(v: number): (number, number, number, number)
	v = v % TWO32
	local a = v % 65536
	local b = math.floor(v / 65536) % 65536
	return a, b, 0, 0
end

local function mulAdd64(hi: number, lo: number, mhi: number, mlo: number, inc: number): (number, number)

	local l0 = lo % 65536
	local l1 = math.floor(lo / 65536) % 65536
	local h0 = hi % 65536
	local h1 = math.floor(hi / 65536) % 65536
	local m0 = mlo % 65536
	local m1 = math.floor(mlo / 65536) % 65536
	local mh0 = mhi % 65536
	local mh1 = math.floor(mhi / 65536) % 65536

	local r0 = l0 * m0
	local r1 = l1 * m0 + l0 * m1 + math.floor(r0 / 65536)
	r0 = r0 % 65536
	local r2 = h0 * m0 + l1 * m1 + l0 * mh0 + math.floor(r1 / 65536)
	r1 = r1 % 65536
	local r3 = h1 * m0 + h0 * m1 + l1 * mh0 + l0 * mh1 + math.floor(r2 / 65536)
	r2 = r2 % 65536
	r3 = r3 % 65536

	local carry = inc
	carry += r0
	r0 = carry % 65536
	carry = math.floor(carry / 65536)
	carry += r1
	r1 = carry % 65536
	carry = math.floor(carry / 65536)
	carry += r2
	r2 = carry % 65536
	carry = math.floor(carry / 65536)
	carry += r3
	r3 = carry % 65536
	local nhi = (r3 * 65536 + r2) % TWO32
	local nlo = (r1 * 65536 + r0) % TWO32
	return nhi, nlo
end

local function rotr32(v: number, r: number): number
	r = r % 32
	if r == 0 then
		return v % TWO32
	end
	v = v % TWO32
	return (math.floor(v / (2 ^ r)) + ((v % (2 ^ r)) * (2 ^ (32 - r)))) % TWO32
end

local function pcgOut32(hi: number, lo: number): number

	local stateHi = (hi % TWO32)
	local stateLo = (lo % TWO32)
	local s27 = (stateHi * 32 + math.floor(stateLo / 134217728)) % TWO32
	local s45 = math.floor(stateHi / 8192) % TWO32

	local x = bit32.bxor(s27, s45)
	local rot = math.floor(stateHi / 134217728) % 32
	return rotr32(x, rot)
end

function Fidelity.pcgSeed(seed: number): (number, number)
	seed = math.floor(tonumber(seed) or 0)

	local lo = (PCG_INC + (seed % TWO32)) % TWO32
	local hi = math.floor(seed / TWO32) % TWO32

	if PCG_INC + (seed % TWO32) >= TWO32 then
		hi = (hi + 1) % TWO32
	end
	return mulAdd64(hi, lo, PCG_M_HI, PCG_M_LO, PCG_INC)
end

function Fidelity.pcgStep(hi: number, lo: number): (number, number)
	return mulAdd64(hi, lo, PCG_M_HI, PCG_M_LO, PCG_INC)
end

function Fidelity.pcgNext32(hi: number, lo: number): number
	return pcgOut32(hi, lo)
end

function Fidelity.pcgDouble(hi: number, lo: number): (number, number, number)
	local rLow = pcgOut32(hi, lo)
	local n1hi, n1lo = mulAdd64(hi, lo, PCG_M_HI, PCG_M_LO, PCG_INC)
	local rHigh = pcgOut32(n1hi, n1lo)
	local n2hi, n2lo = mulAdd64(n1hi, n1lo, PCG_M_HI, PCG_M_LO, PCG_INC)
	local r64 = rHigh * TWO32 + rLow
	local v = r64 / 18446744073709551616
	return v, n2hi, n2lo
end

Fidelity.ORDERS = {
	utf8 = { "offset", "codepoint", "nfdnormalize", "char", "codes", "len", "graphemes", "nfcnormalize", "charpattern" },
	math = {
		"log", "e", "ldexp", "deg", "cosh", "round", "random", "frexp", "tanh", "floor",
		"max", "sqrt", "modf", "huge", "sqrt2", "pow", "isnan", "acos", "phi", "tau",
		"exp", "pi", "isfinite", "tan", "cos", "isinf", "atan", "map", "sign", "ceil",
		"clamp", "noise", "abs", "nan", "sinh", "asin", "min", "randomseed", "fmod", "rad",
		"atan2", "log10", "sin", "lerp",
	},
	debug = {
		"dumpheap", "getconstants", "getproto", "setmemorycategory", "profilebegin", "loadmodule",
		"traceback", "getstack", "getregistry", "setmetatable", "getupvalues", "getupvalue",
		"getmemorycategory", "resetmemorycategory", "setupvalue", "validlevel", "isvalidlevel",
		"dumpcodesize", "setstack", "getconstant", "profileend", "info", "getinfo", "getprotos",
		"setconstant", "getmetatable", "dumprefs",
	},
	task = { "defer", "cancel", "wait", "desynchronize", "synchronize", "delay", "spawn" },
}

function Fidelity.spoofInfo(fn: any, options: string): ({ any }, number)
	local name = names[fn] or "?"
	local out: { any } = {}
	local n = 0
	for i = 1, #options do
		local flag = string.sub(options, i, i)
		if flag == "s" then
			n += 1
			out[n] = "[C]"
		elseif flag == "l" then
			n += 1
			out[n] = -1
		elseif flag == "n" then
			n += 1
			out[n] = name
		elseif flag == "a" then
			n += 1
			out[n] = 0
			n += 1
			out[n] = true
		elseif flag == "f" then
			n += 1
			out[n] = fn
		end
	end
	return out, n
end

return Fidelity
