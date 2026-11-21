local Symbol = require("./symbol")

local Serializer = {}

export type Options = {

	pretty: boolean?,

	maxDepth: number?,

	maxArrayItems: number?,

	maxTableKeys: number?,

	maxStringBytes: number?,

	indent: string?,
}

type Resolved = {
	pretty: boolean,
	maxDepth: number,
	maxArrayItems: number,
	maxTableKeys: number,
	maxStringBytes: number,
	indent: string,
}

local DEFAULTS: Resolved = {
	pretty = true,
	maxDepth = 8,
	maxArrayItems = 256,
	maxTableKeys = 512,
	maxStringBytes = 2048,
	indent = "    ",
}

local RESERVED: { [string]: true } = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
	["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
	["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
	["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
	["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
	["while"] = true,

	["continue"] = true,
}

local SHORT_ESCAPES: { [number]: string } = {
	[7] = "\\a", [8] = "\\b", [9] = "\\t", [10] = "\\n",
	[11] = "\\v", [12] = "\\f", [13] = "\\r",
	[34] = '\\"', [92] = "\\\\",
}

local function resolve(options: Options?): Resolved
	if not options then
		return DEFAULTS
	end
	return {
		pretty = if options.pretty ~= nil then options.pretty else DEFAULTS.pretty,
		maxDepth = options.maxDepth or DEFAULTS.maxDepth,
		maxArrayItems = options.maxArrayItems or DEFAULTS.maxArrayItems,
		maxTableKeys = options.maxTableKeys or DEFAULTS.maxTableKeys,
		maxStringBytes = options.maxStringBytes or DEFAULTS.maxStringBytes,
		indent = options.indent or DEFAULTS.indent,
	}
end

function Serializer.stringLiteral(value: string, maxBytes: number?): string
	local limit = maxBytes or DEFAULTS.maxStringBytes
	local truncated = false
	local source = value
	if #source > limit then
		source = string.sub(source, 1, limit)
		truncated = true
	end

	local out: { string } = { '"' }
	local n = 1
	local length = #source

	for i = 1, length do
		local byte = string.byte(source, i)
		local short = SHORT_ESCAPES[byte]
		if short then
			n += 1
			out[n] = short
		elseif byte < 32 or byte == 127 then

			local nextByte = if i < length then string.byte(source, i + 1) else nil
			local nextIsDigit = nextByte ~= nil and nextByte >= 48 and nextByte <= 57
			n += 1
			out[n] = if nextIsDigit
				then string.format("\\%03d", byte)
				else string.format("\\%d", byte)
		elseif byte > 127 then

			n += 1
			out[n] = string.format("\\%03d", byte)
		else
			n += 1
			out[n] = string.char(byte)
		end
	end

	n += 1
	out[n] = '"'

	local literal = table.concat(out)
	if truncated then
		local omitted = #value - limit
		literal ..= string.format(" --[[ +%d bytes truncated ]]", omitted)
	end
	return literal
end

function Serializer.numberLiteral(value: number): string
	if value ~= value then
		return "0/0"
	elseif value == math.huge then
		return "math.huge"
	elseif value == -math.huge then
		return "-math.huge"
	end

	if value % 1 == 0 and math.abs(value) < 2 ^ 53 then
		return string.format("%d", value)
	end

	local shortest = string.format("%.14g", value)
	if tonumber(shortest) == value then
		return shortest
	end
	return string.format("%.17g", value)
end

function Serializer.isIdentifier(name: string): boolean
	if RESERVED[name] then
		return false
	end
	return string.match(name, "^[%a_][%w_]*$") ~= nil
end

type State = {
	options: Resolved,

	active: { [any]: boolean },

	seen: { [any]: boolean },
}

local encodeValue: (value: any, depth: number, state: State) -> string

local function encodeKey(key: any, depth: number, state: State): string
	if type(key) == "string" and Serializer.isIdentifier(key) then
		return key .. " = "
	end
	return "[" .. encodeValue(key, depth, state) .. "] = "
end

local function rawTypeOf(value: any): string
	return type(value)
end

local function encodeTable(value: any, depth: number, state: State): string
	local options = state.options

	if state.active[value] then
		return "nil --[[ cyclic reference ]]"
	end
	if depth >= options.maxDepth then
		return "nil --[[ max depth reached ]]"
	end

	state.active[value] = true
	state.seen[value] = true

	local parts: { string } = {}
	local count = 0
	local truncatedNote: string? = nil

	local arrayLength = 0
	local ok, len = pcall(function()
		return #value
	end)
	if ok and type(len) == "number" then
		arrayLength = len
	end

	local emittedArray = 0
	for i = 1, arrayLength do
		if emittedArray >= options.maxArrayItems then
			truncatedNote = string.format("--[[ +%d array entries ]]", arrayLength - emittedArray)
			break
		end
		local item = rawget(value, i)
		count += 1
		parts[count] = encodeValue(item, depth + 1, state)
		emittedArray += 1
	end

	local hashKeys: { any } = {}
	local hashCount = 0
	for key in pairs(value) do
		local isArrayIndex = type(key) == "number"
			and key % 1 == 0
			and key >= 1
			and key <= arrayLength
		if not isArrayIndex then
			hashCount += 1
			hashKeys[hashCount] = key
		end
	end

	table.sort(hashKeys, function(a, b)
		local ta, tb = rawTypeOf(a), rawTypeOf(b)
		if ta ~= tb then
			return ta < tb
		end
		if ta == "number" or ta == "string" then
			return (a :: any) < (b :: any)
		end
		return tostring(a) < tostring(b)
	end)

	local emittedHash = 0
	for _, key in ipairs(hashKeys) do
		if count >= options.maxTableKeys then
			truncatedNote = string.format("--[[ +%d keys ]]", hashCount - emittedHash)
			break
		end
		local item = rawget(value, key)
		count += 1
		parts[count] = encodeKey(key, depth + 1, state) .. encodeValue(item, depth + 1, state)
		emittedHash += 1
	end

	state.active[value] = nil

	if count == 0 then
		return if truncatedNote then "{ " .. truncatedNote .. " }" else "{}"
	end

	if not options.pretty then
		local body = table.concat(parts, ", ")
		if truncatedNote then
			body ..= " " .. truncatedNote
		end
		return "{ " .. body .. " }"
	end

	local pad = string.rep(options.indent, depth + 1)
	local closePad = string.rep(options.indent, depth)
	local body = pad .. table.concat(parts, ",\n" .. pad)
	if truncatedNote then
		body ..= ",\n" .. pad .. truncatedNote
	end
	return "{\n" .. body .. "\n" .. closePad .. "}"
end

function encodeValue(value: any, depth: number, state: State): string

	local expression = Symbol.expression(value)
	if expression then
		return expression
	end

	local valueType = type(value)

	if value == nil then
		return "nil"
	elseif valueType == "boolean" then
		return tostring(value)
	elseif valueType == "number" then
		return Serializer.numberLiteral(value)
	elseif valueType == "string" then
		return Serializer.stringLiteral(value, state.options.maxStringBytes)
	elseif valueType == "table" then
		return encodeTable(value, depth, state)
	elseif valueType == "function" then

		return "function() end --[[ callback ]]"
	elseif valueType == "thread" then
		return "coroutine.create(function() end) --[[ thread ]]"
	elseif valueType == "buffer" then
		local ok, contents = pcall(function()
			return buffer.tostring(value :: any)
		end)
		if ok then
			return "buffer.fromstring(" .. Serializer.stringLiteral(contents, state.options.maxStringBytes) .. ")"
		end
		return "nil --[[ buffer ]]"
	elseif valueType == "vector" then
		local ok, text = pcall(function()
			local v = value :: any
			return string.format(
				"Vector3.new(%s, %s, %s)",
				Serializer.numberLiteral(v.x),
				Serializer.numberLiteral(v.y),
				Serializer.numberLiteral(v.z)
			)
		end)
		if ok then
			return text
		end
		return "nil --[[ vector ]]"
	end

	local ok, text = pcall(tostring, value)
	if ok and type(text) == "string" then
		return "nil --[[ " .. valueType .. ": " .. text .. " ]]"
	end
	return "nil --[[ " .. valueType .. " ]]"
end

function Serializer.value(value: any, options: Options?): string
	local state: State = {
		options = resolve(options),
		active = {},
		seen = {},
	}
	return encodeValue(value, 0, state)
end

function Serializer.arguments(args: { any }, count: number?, options: Options?): string
	local resolved = resolve(options)

	local inline: Resolved = table.clone(resolved)
	inline.pretty = false

	local state: State = { options = inline, active = {}, seen = {} }
	local total = count or #args
	local parts: { string } = table.create(total)

	for i = 1, total do
		parts[i] = encodeValue(args[i], 0, state)
	end
	return table.concat(parts, ", ")
end

function Serializer.index(base: string, key: any): string
	if type(key) == "string" and Serializer.isIdentifier(key) then
		return base .. "." .. key
	end
	return base .. "[" .. Serializer.value(key, { pretty = false }) .. "]"
end

return Serializer
