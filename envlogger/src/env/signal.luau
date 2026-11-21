local Symbol = require("../core/symbol")

local Signal = {}

local liveSignals: { any } = {}
local liveSlots: { [any]: number } = {}
local liveHoles = 0

local MAX_LIVE = 4096

local function register(signal: any)
	if liveSlots[signal] ~= nil then
		return
	end
	if #liveSignals - liveHoles >= MAX_LIVE then
		return
	end
	liveSignals[#liveSignals + 1] = signal
	liveSlots[signal] = #liveSignals
end

local function unregister(signal: any)
	local index = liveSlots[signal]
	if index == nil then
		return
	end

	liveSignals[index] = false
	liveSlots[signal] = nil
	liveHoles += 1
	if liveHoles > 64 and liveHoles * 2 > #liveSignals then
		local kept: { any } = {}
		for _, entry in ipairs(liveSignals) do
			if entry then
				kept[#kept + 1] = entry
				liveSlots[entry] = #kept
			end
		end
		liveSignals = kept
		liveHoles = 0
	end
end

function Signal.reset()
	for _, signal in ipairs(liveSignals) do
		if signal and signal._clear ~= nil then
			signal._clear()
		end
	end
	liveSignals = {}
	liveSlots = {}
	liveHoles = 0
end

function Signal.fireFrame(dt: number)

	local snapshot = liveSignals
	for index = 1, #snapshot do
		local signal = snapshot[index]
		if signal and signal._fire ~= nil then
			signal._fire(dt)
		end
	end
end

function Signal.new(name: string?, opts: any?): any
	local callbacks: { any } = {}
	local connections: { any } = {}
	local signal: any = {}

	local frameFires = opts ~= nil and opts.frameFires == true

	local traceRef = opts ~= nil and opts.trace or nil
	local traceNest = opts ~= nil and opts.nest or 0
	local connectExpr = opts ~= nil and opts.connectExpr or name or "Signal"
	local connectBaseId = opts ~= nil and opts.baseId or nil
	local connectEvent = opts ~= nil and opts.event or nil

	local function connect(callback: any): any
		callbacks[#callbacks + 1] = callback
		if traceRef then
			traceRef:push(
				"namecall",
				connectExpr .. ":Connect(function() ... end)",
				traceNest,
				{
					base = connectExpr,
					key = "Connect",
					callback = true,
					baseId = connectBaseId,
					event = connectEvent,
				}
			)
		end

		if frameFires then
			register(signal)
		end
		local connection: any
		connection = {
			Connected = true,
			Disconnect = function(...: any)

				if select("#", ...) > 0 and (... :: any) == nil then
					error("invalid argument #1 to 'Disconnect' (RBXScriptConnection expected, got nil)", 2)
				end
				connection.Connected = false
				for i, entry in ipairs(connections) do
					if entry == connection then
						table.remove(connections, i)
						break
					end
				end
				for i = #callbacks, 1, -1 do
					if callbacks[i] == callback then
						table.remove(callbacks, i)
						break
					end
				end
				if #callbacks == 0 then
					unregister(signal)
				end
			end,
		}
		Symbol.tag(connection, {
			kind = "datatype",
			expression = (name or "Signal") .. ":Connect(function() end --[[ callback ]])",
			typeName = "RBXScriptConnection",
		})
		require("./fidelity").registerTree(connection)
		connections[#connections + 1] = connection
		return connection
	end

	signal.Connect = function(_self: any, callback: any): any
		return connect(callback)
	end
	signal.Once = function(_self: any, callback: any): any
		local connection: any
		local wrapped = function(...: any)
			if connection.Connected then
				connection.Disconnect()
			end
			callback(...)
		end
		connection = connect(wrapped)
		return connection
	end
	signal.Wait = function(_self: any): any

		return 1 / 60
	end
	function signal._fire(...: any)

		local count = #callbacks
		if count == 0 then
			return
		end
		if count == 1 then

			local only = callbacks[1]
			pcall(only, ...)
			return
		end
		local snapshot = table.clone(callbacks)
		for _, callback in ipairs(snapshot) do
			pcall(callback, ...)
		end
	end

	function signal._clear()
		for index = #connections, 1, -1 do
			local connection = connections[index]
			if type(connection) == "table" then
				connection.Connected = false
			end
			connections[index] = nil
		end
		for index = #callbacks, 1, -1 do
			callbacks[index] = nil
		end
	end
	signal.Connected = true

	Symbol.tag(signal, {
		kind = "datatype",
		expression = name or "Signal",
		typeName = "RBXScriptSignal",
	})
	require("./fidelity").registerTree(signal)
	return signal
end

function Signal.isSignal(value: any): boolean
	return type(value) == "table" and Symbol.typeName(value) == "RBXScriptSignal"
end

return Signal
