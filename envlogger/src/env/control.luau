local Sanitize = require("../core/sanitize")
local Serializer = require("../core/serializer")
local Spy = require("../core/spy")

local Control = {}

export type Options = {
	trace: any,
	nest: number,

	onOutput: ((channel: string, text: string) -> ())?,

	checkBudget: (() -> boolean)?,

	resolveName: ((value: any) -> string?)?,
}

type RenderedArgument = {
	text: string,
	isString: boolean,
	console: string?,
}

local function renderValue(unwrapped: any, resolveName: ((value: any) -> string?)?): RenderedArgument
	local valueType = type(unwrapped)
	if valueType == "string" then

		return { text = Sanitize.internalLocation(Sanitize.paths(unwrapped)), isString = true }
	elseif valueType == "number" then
		return { text = Serializer.numberLiteral(unwrapped), isString = false }
	elseif valueType == "boolean" then
		return { text = tostring(unwrapped), isString = false }
	elseif unwrapped == nil then
		return { text = "nil", isString = false }
	elseif valueType == "table" then

		local named = resolveName and resolveName(unwrapped)
		if named then
			return { text = named, isString = false }
		end
	end

	return {
		text = Serializer.value(unwrapped, { pretty = false }),
		isString = false,
	}
end

local function renderArgument(value: any, resolveName: ((value: any) -> string?)?): RenderedArgument
	if Spy.is(value) then
		local rendered: RenderedArgument = { text = Spy.pathOf(value), isString = false }

		local internal = Spy.internalOf(value)
		if internal ~= nil and internal.hasConcrete then
			rendered.console = renderValue(Spy.unwrap(value), resolveName).text
		end
		return rendered
	end
	return renderValue(Spy.unwrap(value), resolveName)
end

function Control.build(options: Options): { [string]: any }
	local trace = options.trace
	local nest = options.nest
	local onOutput = options.onOutput
	local resolveName = options.resolveName

	local globals: { [string]: any } = {}

	local function emit(channel: string, text: string, args: { RenderedArgument }?, console: string?)
		if options.checkBudget and options.checkBudget() then
			error("sandbox budget exceeded")
		end
		trace:push("output", text, nest, { channel = channel, args = args })
		if onOutput then
			onOutput(channel, console or text)
		end
	end

	local function joinArguments(count: number, ...): ({ RenderedArgument }, string, string)
		local args = table.create(count)
		for i = 1, count do
			args[i] = renderArgument((select(i, ...)), resolveName)
		end
		local sourceParts = table.create(count)
		local consoleParts = table.create(count)
		for i = 1, count do
			sourceParts[i] = args[i].text
			consoleParts[i] = args[i].console or args[i].text
		end
		return args, table.concat(sourceParts, "\t"), table.concat(consoleParts, "\t")
	end

	globals.print = function(...)
		local count = select("#", ...)
		if count == 0 then
			emit("print", "", nil)
			return
		end
		local args, source, console = joinArguments(count, ...)
		emit("print", source, args, console)
	end

	globals.warn = function(...)
		local count = select("#", ...)
		if count == 0 then
			emit("warn", "", nil)
			return
		end
		local args, source, console = joinArguments(count, ...)
		emit("warn", source, args, console)
	end

	globals.error = function(message: any, level: number?)
		local rendered = renderArgument(message, resolveName).text
		trace:push("error", rendered, nest, { raised = true })
		local lvl = tonumber(level) or 1
		local rawMsg = Spy.unwrap(message) or rendered

		if tostring(rawMsg) == "" and lvl > 0 then
			error("[string \"\"]:1: ", 0)
		elseif lvl > 0 then
			lvl += 1
		end
		error(rawMsg, lvl)
	end

	globals.assert = function(...: any)
		local total = select("#", ...)
		if total == 0 then

			return assert()
		end
		local args = table.pack(...)
		local condition = args[1]
		local message = args[2]
		if not condition then
			local rendered = if message ~= nil then renderArgument(message, resolveName).text else "assertion failed!"
			trace:push("error", rendered, nest, { assertion = true })
			error(rendered, 2)
		end
		return table.unpack(args, 1, total)
	end

	globals.pcall = function(fn: any, ...)
		local target = Spy.unwrap(fn)
		local results
		if type(target) ~= "function" then

			results = table.pack(pcall(fn, ...))
		else
			results = table.pack(pcall(target, ...))
		end
		if not results[1] then
			local msg = tostring(results[2] or "")
			trace:push("error", "pcall failed: " .. Sanitize.internalLocation(Sanitize.paths(msg)), nest, {
				callee = "pcall",
				raised = false,
			})
		end
		return table.unpack(results, 1, results.n)
	end

	globals.xpcall = function(fn: any, handler: any, ...)
		local target = Spy.unwrap(fn)
		local realHandler = Spy.unwrap(handler)
		if type(realHandler) ~= "function" then
			realHandler = function(err)
				return err
			end
		end
		if type(target) ~= "function" then
			return xpcall(function(...)
				return fn(...)
			end, realHandler, ...)
		end
		return xpcall(target, realHandler, ...)
	end

	globals.ypcall = function(fn: any, ...)
		local target = Spy.unwrap(fn)
		if type(target) ~= "function" then
			return false, "attempt to call a nil value"
		end
		local results = table.pack(pcall(target, ...))
		if results[1] then
			return table.unpack(results, 1, results.n)
		end
		return false, results[2]
	end

	globals.select = function(...: any)
		local total = select("#", ...)
		if total == 0 then

			return select()
		end
		local args = table.pack(...)
		local key = Spy.unwrap(args[1])

		if type(key) == "string" and key == "#" then
			return total - 1
		end
		if type(key) ~= "number" or key == 0 or key ~= key then

			return select(key)
		end
		local results = table.pack(select(key, table.unpack(args, 2, total)))
		return table.unpack(results, 1, results.n)
	end

	return globals
end

return Control
