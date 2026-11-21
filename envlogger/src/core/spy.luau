local Serializer = require("./serializer")
local Symbol = require("./symbol")
local Trace = require("./trace")

local Spy = {}

export type Config = {
	trace: Trace.Class,
	nest: number,

	maxDepth: number?,

	onCall: ((path: string, args: { any }, count: number) -> (boolean, any))?,

	onNamecall: ((path: string, method: string, args: { any }, count: number) -> (boolean, any))?,

	onIndex: ((path: string, key: any) -> (boolean, any, boolean?))?,

	onWrite: ((proxy: any, key: any, value: any) -> ())?,

	onRead: ((proxy: any, key: any, value: any) -> (any, boolean))?,

	checkBudget: (() -> boolean)?,
}

type Internal = {

	path: string,

	renderId: number,

	concrete: any,
	hasConcrete: boolean,
	depth: number,
	config: Config,

	children: { [any]: any },

	absent: { [any]: boolean },

	receiver: any,
	memberName: string?,

	unique: boolean?,
}

local state: { [any]: Internal } = setmetatable({}, { __mode = "k" })

local nextRenderId = 0

function Spy.internalOf(value: any): Internal?

	if type(value) ~= "table" and type(value) ~= "function" and type(value) ~= "userdata" then
		return nil
	end
	return state[value]
end

function Spy.is(value: any): boolean
	return Spy.internalOf(value) ~= nil
end

function Spy.renderIdOf(value: any): number?
	local internal = Spy.internalOf(value)
	if internal then
		return internal.renderId
	end
	return nil
end

function Spy.markUnique(value: any): any
	local internal = Spy.internalOf(value)
	if internal then
		internal.unique = true
	end
	return value
end

function Spy.pathOf(value: any): string
	local internal = Spy.internalOf(value)
	if internal then
		return internal.path
	end
	local tagged = Symbol.expression(value)
	if tagged then
		return tagged
	end
	return Serializer.value(value, { pretty = false })
end

function Spy.rename(value: any, name: string): any
	local internal = Spy.internalOf(value)
	if internal then
		internal.path = name
	end
	return value
end

function Spy.unwrap(value: any, seen: { [any]: any }?): any
	local internal = Spy.internalOf(value)
	if internal then
		return if internal.hasConcrete then internal.concrete else nil
	end
	if type(value) ~= "table" then
		return value
	end

	if Symbol.isKind(value, "env") then
		return value
	end

	if type(value) == "userdata" then
		return value
	end

	local visited = seen or {}
	if visited[value] then
		return visited[value]
	end

	local needsCopy = false
	for _, item in pairs(value) do
		if Spy.is(item) then
			needsCopy = true
			break
		end
	end
	if not needsCopy then
		return value
	end

	local copy = {}
	visited[value] = copy
	for key, item in pairs(value) do
		copy[key] = Spy.unwrap(item, visited)
	end
	return copy
end

local function EMPTY_ITERATOR(): any
	return nil
end

local ITERATOR_FACTORIES: { [string]: boolean } = {
	pairs = true,
	ipairs = true,
}

local ITERATOR_STEPPERS: { [string]: boolean } = {
	next = true,
}

local metatable: any = {}

local function newProxy(): any
	local ok, proxy = pcall(newproxy, true)
	if not ok or type(proxy) ~= "userdata" then

		return setmetatable({}, metatable)
	end
	local mt = getmetatable(proxy)
	if type(mt) ~= "table" then
		return setmetatable({}, metatable)
	end
	for key, value in pairs(metatable) do
		mt[key] = value
	end
	return proxy
end

function Spy.new(path: string, config: Config, concrete: any?, hasConcrete: boolean?, depth: number?): any
	local proxy = newProxy()
	nextRenderId += 1
	state[proxy] = {
		path = path,
		renderId = nextRenderId,
		concrete = concrete,
		hasConcrete = hasConcrete or false,
		depth = depth or 0,
		config = config,
		children = {},
		absent = {},
	}
	Symbol.tag(proxy, {
		kind = "spy",
		expression = path,
		typeName = "Instance",
	})
	return proxy
end

local function isScalar(value: any): boolean
	local valueType = type(value)
	return valueType == "number"
		or valueType == "string"
		or valueType == "boolean"
		or valueType == "vector"
		or valueType == "buffer"
end

local function derive(internal: Internal, path: string, concrete: any, hasConcrete: boolean): any
	if hasConcrete and isScalar(concrete) then
		return concrete
	end
	return Spy.new(path, internal.config, concrete, hasConcrete, internal.depth + 1)
end

function metatable.__index(proxy: any, key: any): any
	local internal = state[proxy]
	if not internal then
		return nil
	end

	local config = internal.config

	if config == nil then
		return nil
	end
	if config.checkBudget and config.checkBudget() then
		error("sandbox budget exceeded")
	end

	if internal.absent[key] then
		return nil
	end
	local cached = internal.children[key]
	if cached ~= nil then
		if config.onRead then
			local replacement, replaceNow = config.onRead(proxy, key, cached)
			if replaceNow then
				return replacement
			end
		end
		return cached
	end

	local expression = Serializer.index(internal.path, key)

	config.trace:push("index", expression, config.nest, {
		base = internal.path,
		key = if type(key) == "string" then key else Serializer.value(key, { pretty = false }),
		renderId = internal.renderId,
	})

	if type(key) == "number" and isUserdata(proxy) then
		local descriptor = Symbol.get(proxy)
		local detail = if descriptor then descriptor.detail else nil
		local className = if type(detail) == "table" and type(detail.className) == "string"
			then detail.className
			else "Instance"
		error(string.format(
			"%s is not a valid member of %s \"%s\"",
			tostring(key),
			className,
			tostring(key)
		), 0)
	end

	local limit = config.maxDepth or 24
	if internal.depth >= limit then
		internal.absent[key] = true
		return nil
	end

	if config.onIndex then
		local supplied, value, volatile = config.onIndex(internal.path, key)
		if supplied then

			if value == nil then
				internal.absent[key] = true
				return nil
			end

			if not volatile then
				internal.children[key] = value
			end

			if type(key) == "string" then
				local made = state[value]
				if made and made.memberName == nil then
					local descriptor = Symbol.get(value)
					local detail = if descriptor then descriptor.detail else nil
					if type(detail) == "table" and detail.unknownMember ~= nil then
						made.receiver = proxy
						made.memberName = key
					end
				end
			end
			return value
		end
	end

	local concrete, hasConcrete = nil, false
	if internal.hasConcrete and type(internal.concrete) == "table" then
		local ok, value = pcall(function()
			return (internal.concrete :: any)[key]
		end)
		if ok and value ~= nil then
			concrete, hasConcrete = value, true
		end
	end

	local child = derive(internal, expression, concrete, hasConcrete)

	local childInternal = state[child]
	if childInternal and type(key) == "string" then
		childInternal.receiver = proxy
		childInternal.memberName = key
	end

	if type(child) == "function" then
		local dualChild: any = setmetatable({}, {
			__call = function(_self, ...: any): any
				return (child :: any)(...)
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
		Symbol.tag(dualChild, {
			kind = "closure",
			expression = expression,
			typeName = "function",
			detail = { dualNature = true, callable = true, memberOf = internal.path },
		})
		internal.children[key] = dualChild
		return dualChild
	end

	internal.children[key] = child
	return child
end

function metatable.__newindex(proxy: any, key: any, value: any)
	local internal = state[proxy]
	if not internal then
		return
	end
	local config = internal.config
	if config.checkBudget and config.checkBudget() then
		error("sandbox budget exceeded")
	end
	local target = Serializer.index(internal.path, key)

	config.trace:push("newindex", target .. " = " .. Spy.pathOf(value), config.nest, {
		base = internal.path,
		key = if type(key) == "string" then key else Serializer.value(key, { pretty = false }),
		value = Spy.pathOf(value),
		renderId = internal.renderId,
		valueId = Spy.renderIdOf(value),
	})

	if config.onWrite then
		config.onWrite(proxy, key, value)
	end

	internal.children[key] = value
	if value == nil then
		internal.absent[key] = true
	else
		internal.absent[key] = nil
	end
end

local function isUserdata(proxy: any): boolean
	local descriptor = Symbol.get(proxy)
	return descriptor ~= nil and (descriptor.kind == "instance" or descriptor.kind == "service")
end

local function config_soft(v: any): boolean
	local internal = state[v]
	return internal ~= nil and internal.config ~= nil and internal.config.softInstanceCall == true
end

function metatable.__call(proxy: any, ...): ...any
	local internal = state[proxy]
	if not internal then
		return nil
	end
	local config = internal.config
	if config.checkBudget and config.checkBudget() then
		error("sandbox budget exceeded")
	end

	if isUserdata(proxy) then
		if internal.memberName == nil then
			if config.softInstanceCall then
				return nil
			end
			error("attempt to call a Instance value", 0)
		end
		local descriptor = Symbol.get(proxy)
		local detail = descriptor and descriptor.detail
		if type(detail) == "table" and detail.unknownMember ~= nil then

			local receiverState = if internal.receiver ~= nil then state[internal.receiver] else nil
			local receiverDescriptor = if receiverState then Symbol.get(internal.receiver) else nil
			local receiverDetail = if receiverDescriptor then receiverDescriptor.detail else nil
			local throughUnknown = type(receiverDetail) == "table" and receiverDetail.unknownMember ~= nil
			if not throughUnknown then
				error(string.format(
					"%s is not a valid member of %s",
					tostring(detail.unknownMember),
					tostring(detail.ownerName)
				), 0)
			end

		end
	end

	local count = select("#", ...)
	local args = { ... }

	local isMethod = count > 0
		and internal.memberName ~= nil
		and rawequal(args[1], internal.receiver)

	local renderedArgs: string
	local expression: string
	local method: string? = nil

	if isMethod then
		local shifted = table.create(math.max(count - 1, 0))
		for i = 2, count do
			shifted[i - 1] = args[i]
		end
		renderedArgs = Serializer.arguments(shifted, count - 1)
		method = internal.memberName
		expression = Spy.pathOf(internal.receiver) .. ":" .. (method :: string) .. "(" .. renderedArgs .. ")"
	else
		renderedArgs = Serializer.arguments(args, count)
		expression = internal.path .. "(" .. renderedArgs .. ")"
	end

	config.trace:push(if isMethod then "namecall" else "call", expression, config.nest, {
		callee = if isMethod then Spy.pathOf(internal.receiver) else internal.path,
		method = method,
		arguments = renderedArgs,
		argumentCount = if isMethod then count - 1 else count,
	})

	if config.onCall then
		local handled, result = config.onCall(internal.path, args, count)
		if handled then
			return result
		end
	end

	local baseName = internal.memberName or internal.path

	if ITERATOR_FACTORIES[baseName] then
		local subject = Spy.unwrap(args[1])
		if type(subject) == "table" then
			return next, subject :: any
		end
		return EMPTY_ITERATOR, proxy
	end

	if ITERATOR_STEPPERS[baseName] then

		local subject = Spy.unwrap(args[1])
		if type(subject) == "table" then
			local ok, key, value = pcall(next, subject :: any, Spy.unwrap(args[2]))
			if ok then
				return key, value
			end
		end
		return nil
	end

	return derive(internal, expression, nil, false)
end

local function addressOf(path: string): string
	local hash = 0x7f000000
	for i = 1, #path do
		hash = bit32.bxor(hash * 33 + string.byte(path, i), 0x5bd1e995)
		hash = bit32.band(hash, 0x7FFFFFFF)
	end
	return string.format("%016x", hash)
end

function metatable.__tostring(proxy: any): string
	local internal = state[proxy]
	if not internal then
		return "nil"
	end
	if internal.hasConcrete then
		local ok, text = pcall(tostring, internal.concrete)
		if ok then
			return text
		end
	end

	if isUserdata(proxy) then
		local descriptor = Symbol.get(proxy)
		local isDataModel = descriptor ~= nil and descriptor.detail ~= nil
			and descriptor.detail.className == "DataModel"
		if not isDataModel then

			local name: string? = nil
			local cached = internal.children["Name"]
			if type(cached) == "string" and cached ~= "" then
				name = cached
			elseif internal.config.onIndex then
				local supplied, value = internal.config.onIndex(internal.path, "Name")
				if supplied and type(value) == "string" and value ~= "" then
					name = value
				end
			end
			if name then
				return name
			end
		end
		return "userdata: 0x" .. addressOf(internal.path)
	end
	return internal.path
end

function metatable.__concat(left: any, right: any): any

	if isUserdata(left) or isUserdata(right) then
		error("attempt to concatenate a userdata value")
	end
	local internal = state[left] or state[right]
	local config = internal.config
	if config.checkBudget and config.checkBudget() then
		error("sandbox budget exceeded")
	end

	local function render(value: any): string
		local own = state[value]
		if own then
			if own.hasConcrete and type(own.concrete) == "string" then
				return own.concrete
			end
			return own.path
		end
		return tostring(value)
	end

	local text = render(left) .. render(right)
	config.trace:push("index", text, config.nest, { concat = true })
	return text
end

function metatable.__len(proxy: any): number
	if isUserdata(proxy) then

		error("attempt to get length of a userdata value (Instance)")
	end
	local internal = state[proxy]
	if internal and internal.hasConcrete then
		local ok, length = pcall(function()
			return #(internal.concrete :: any)
		end)
		if ok and type(length) == "number" then
			return length
		end
	end
	return 0
end

function metatable.__eq(left: any, right: any): boolean

	if rawequal(left, right) then
		return true
	end
	local a, b = state[left], state[right]
	if a and b then
		if a.hasConcrete and b.hasConcrete then
			return a.concrete == b.concrete
		end

		if a.unique or b.unique then
			return false
		end
		return a.path == b.path
	end

	if a and a.hasConcrete then
		return a.concrete == right
	end
	if b and b.hasConcrete then
		return b.concrete == left
	end
	return false
end

function metatable.__iter(proxy: any)
	local internal = state[proxy]
	if internal and internal.hasConcrete and type(internal.concrete) == "table" then
		return next, internal.concrete :: any
	end

	return EMPTY_ITERATOR, proxy
end

local ARITHMETIC: { [string]: (a: any, b: any) -> any } = {
	__add = function(a, b)
		return a + b
	end,
	__sub = function(a, b)
		return a - b
	end,
	__mul = function(a, b)
		return a * b
	end,
	__div = function(a, b)
		return a / b
	end,
	__idiv = function(a, b)
		return a // b
	end,
	__mod = function(a, b)
		return a % b
	end,
	__pow = function(a, b)
		return a ^ b
	end,
}

for name, operation in pairs(ARITHMETIC) do
	metatable[name] = function(left: any, right: any): any
		if isUserdata(left) or isUserdata(right) then

			if config_soft(left) or config_soft(right) then
				return 0
			end
			error("attempt to perform arithmetic on a userdata value")
		end
		local a, b = state[left], state[right]
		local lhs = if a then (if a.hasConcrete then a.concrete else nil) else left
		local rhs = if b then (if b.hasConcrete then b.concrete else nil) else right

		if type(lhs) ~= "number" then
			lhs = tonumber(lhs) or 0
		end
		if type(rhs) ~= "number" then
			rhs = tonumber(rhs) or 0
		end

		local ok, result = pcall(operation, lhs, rhs)
		if ok and type(result) == "number" and result == result then
			return result
		end
		return 0
	end
end

local function numOf(v: any): number?
	if type(v) == "number" then
		return v
	end
	local internal = state[v]
	if internal and internal.hasConcrete and type(internal.concrete) == "number" then
		return internal.concrete
	end
	return nil
end

local function guardArith(a: any, b: any, op: string, mul: boolean): any
	local na = numOf(a) or 0
	local nb = numOf(b) or 0
	if mul then
		if op == "/" then
			if nb == 0 then
				return 0
			end
			return na / nb
		end
		if op == "%" then
			if nb == 0 then
				return 0
			end
			return na % nb
		end
		if op == "^" then
			return na ^ nb
		end
		return na * nb
	end
	if op == "+" then
		return na + nb
	end
	return na - nb
end

metatable.__add = function(left: any, right: any): any return guardArith(left, right, "+", false) end
metatable.__sub = function(left: any, right: any): any return guardArith(left, right, "-", false) end
metatable.__mul = function(left: any, right: any): any return guardArith(left, right, "*", true) end
metatable.__div = function(left: any, right: any): any return guardArith(left, right, "/", true) end
metatable.__mod = function(left: any, right: any): any return guardArith(left, right, "%", true) end
metatable.__pow = function(left: any, right: any): any return guardArith(left, right, "^", true) end

metatable.__unm = function(proxy: any): any
	if isUserdata(proxy) then
		if config_soft(proxy) then
			return 0
		end
		error("attempt to perform arithmetic on a userdata value")
	end
	local internal = state[proxy]
	if internal and internal.hasConcrete and type(internal.concrete) == "number" then
		return -internal.concrete
	end
	return 0
end

local COMPARISON: { [string]: (a: any, b: any) -> boolean } = {
	__lt = function(a, b)
		return a < b
	end,
	__le = function(a, b)
		return a <= b
	end,
}

for name, operation in pairs(COMPARISON) do
	metatable[name] = function(left: any, right: any): boolean
		if isUserdata(left) or isUserdata(right) then

			error("attempt to compare userdata values")
		end
		local a, b = state[left], state[right]
		local lhs = if a then (if a.hasConcrete then a.concrete else nil) else left
		local rhs = if b then (if b.hasConcrete then b.concrete else nil) else right

		if lhs ~= nil and rhs ~= nil and type(lhs) == type(rhs) then
			local ok, result = pcall(operation, lhs, rhs)
			if ok then
				return result
			end
		end
		return false
	end
end

metatable.__metatable = "The metatable is locked"

function Spy.root(name: string, config: Config, concrete: any?): any
	return Spy.new(name, config, concrete, concrete ~= nil, 0)
end

return Spy
