local CFG = __CONFIG or {}
local MAX_STMTS = CFG.max_stmts or 250000
local MAX_BLOCK = CFG.max_block or 25000
local MAX_WAITS = CFG.max_waits or 50
local MAX_DEPTH = CFG.max_depth or 24
local TIME_BUDGET = CFG.time_budget or 30

local R = {
	type = type, typeof = typeof, tostring = tostring, tonumber = tonumber,
	pairs = pairs, ipairs = ipairs, next = next, select = select,
	rawget = rawget, rawset = rawset, rawequal = rawequal, rawlen = rawlen,
	setmetatable = setmetatable, getmetatable = getmetatable,
	pcall = pcall, xpcall = xpcall, error = error,
	getfenv = getfenv, setfenv = setfenv, loadstring = loadstring,
	newproxy = newproxy, print = print, clock = os.clock,
	unpack = table.unpack, insert = table.insert, concat = table.concat,
	remove = table.remove, fmt = string.format, rep = string.rep,
	gsub = string.gsub, match = string.match, byte = string.byte,
	sub = string.sub, find = string.find, sort = table.sort,
	floor = math.floor, huge = math.huge, max = math.max,
}
local REAL_G = R.getfenv(0)
local HARNESS_SRC0 = debug.info(1, "s")

local NATIVE = CFG.native and R.typeof(REAL_G.game) == "Instance"
local OUTBUF = {}
if NATIVE then
	R.print = function(...)
		local t = table.pack(...)
		for i = 1, t.n do t[i] = R.tostring(t[i]) end
		R.insert(OUTBUF, R.concat(t, "\t", 1, t.n))

		if CFG.print_tail and #OUTBUF > 2 * CFG.print_tail then
			OUTBUF = table.move(OUTBUF, #OUTBUF - CFG.print_tail + 1, #OUTBUF, 1, {})
		end
	end
end
local START = R.clock()

local LOOP = R.setmetatable({}, { __tostring = function() return "<envlog: loop truncated>" end })
local ABORT = R.setmetatable({}, { __tostring = function() return "<envlog: budget exhausted>" end })
local TAMPER = R.setmetatable({}, { __tostring = function() return "<envlog: anti-tamper suppressed>" end })
local ABORT_REASON = nil
local tamperCount = 0
local TRIGGER, noteTrigger = nil, nil

local ROOT = { lines = {}, waits = {} }
local STACK = { ROOT }
local stmtCount = 0

local CHAIN = { pf = nil, pid = nil, plast = nil }
function CHAIN.get()
	local pf, pid, plast = CHAIN.pf, CHAIN.pid, CHAIN.plast
	local parts = {}
	local lvl = 3
	local inner = nil
	while true do
		local f = debug.info(lvl, "f")
		if f == nil then break end
		local proto = pf[f]
		local id = proto and pid[proto]
		if id then
			if id == 1 and #parts > 0 then inner = parts[1] end
			R.insert(parts, 1, id .. ":" .. R.tostring(plast[id]))
		end
		lvl += 1
	end

	CHAIN.seen = CHAIN.seen or {}
	if inner and parts[1] == "1:" .. R.tostring(plast[1]) then
		local c = R.tonumber(R.match(inner, "^(%d+):"))
		CHAIN.rootCallee = c
		CHAIN.seen[c] = CHAIN.seen[c] or "ok"
	elseif #parts == 1 and R.match(parts[1], "^1:") then
		for c in R.next, CHAIN.seen do CHAIN.seen[c] = "probe" end
	end
	return R.concat(parts, ",")
end

local function curBlock()
	return STACK[#STACK]
end

local abortHits = 0
local function checkBudget()

	if CHAIN.unlimited then return end
	if ABORT_REASON then

		abortHits += 1
		if abortHits > 1 and coroutine.isyieldable() then coroutine.yield(ABORT) end
		R.error(ABORT, 0)
	end
	if stmtCount > MAX_STMTS then
		ABORT_REASON = "statement limit reached"
		R.error(ABORT, 0)
	end
	local now = R.clock()
	if now - START > TIME_BUDGET then
		ABORT_REASON = "time budget exhausted"
		R.error(ABORT, 0)
	end

	if CFG.heartbeat and now - (CFG._hb or START) > CFG.heartbeat then
		CFG._hb = now
		R.print("\0HB\n" .. R.rep(" ", 16384))
	end
end

local function emit(stmt)
	checkBudget()
	if CHAIN.syncGenv and not CHAIN.syncing then CHAIN.syncGenv() end
	local b = curBlock()
	if b.stopped then
		b.stopped += 1
		if b.stopped > 200 then
			ABORT_REASON = "a stopped loop kept running (its error was caught by the script)"
			R.error(ABORT, 0)
		end
		R.error(LOOP, 0)
	end
	stmtCount += 1
	if CHAIN.pf then stmt.chain = CHAIN.get() end
	R.insert(b.lines, stmt)

	for i = #STACK, 1, -1 do
		local rb = STACK[i]
		if rb.isRoot or i == 1 then
			rb.tape = rb.tape or {}
			R.insert(rb.tape, { stmt = stmt, block = b })
			break
		end
	end
	if #b.lines > MAX_BLOCK then
		R.insert(b.lines, { text = "-- [envlog] block truncated after " .. MAX_BLOCK .. " statements" })
		b.stopped = 0
		R.error(LOOP, 0)
	end
	return stmt
end

local function comment(s)
	return emit({ text = "-- " .. s })
end

local INFO = R.setmetatable({}, { __mode = "k" })
local BYID = {}
local nextId = 0
local PMT = {}
local isMethodName, methodFn
local METHODP_REF

local function isP(v)
	return R.type(v) == "userdata" and INFO[v] ~= nil
end

local function newP(info)
	nextId += 1
	info.id = nextId
	info.children = {}
	info.props = {}
	local p = R.newproxy(true)
	local mt = R.getmetatable(p)
	for k, f in PMT do
		mt[k] = f
	end
	INFO[p] = info
	BYID[nextId] = p
	return p
end

local function tok(p)
	return "\1" .. INFO[p].id .. "\2"
end

local function isIdent(s)
	return R.type(s) == "string" and R.match(s, "^[%a_][%w_]*$") ~= nil and not ({
		["and"] = 1, ["break"] = 1, ["do"] = 1, ["else"] = 1, ["elseif"] = 1, ["end"] = 1,
		["false"] = 1, ["for"] = 1, ["function"] = 1, ["if"] = 1, ["in"] = 1, ["local"] = 1,
		["nil"] = 1, ["not"] = 1, ["or"] = 1, ["repeat"] = 1, ["return"] = 1, ["then"] = 1,
		["true"] = 1, ["until"] = 1, ["while"] = 1, ["continue"] = 1,
	})[s]
end

local function quote(s)
	local out = R.gsub(s, '[%c"\\\128-\255]', function(c)
		if c == "\n" then return "\\n" end
		if c == "\t" then return "\\t" end
		if c == "\r" then return "\\r" end
		if c == '"' then return '\\"' end
		if c == "\\" then return "\\\\" end
		local b = R.byte(c)
		if b >= 128 then return c end
		return "\\" .. b
	end)
	return '"' .. out .. '"'
end

local function fmtNumber(n)
	if n ~= n then return "0/0" end
	if n == R.huge then return "math.huge" end
	if n == -R.huge then return "-math.huge" end
	if n == R.floor(n) and n > -1e15 and n < 1e15 then
		return R.fmt("%d", n)
	end
	local s = R.fmt("%.14g", n)
	if R.tonumber(s) ~= n then s = R.fmt("%.17g", n) end
	return s
end

local fmt
local genvTable
local GENVNAME = R.setmetatable({}, { __mode = "k" })
local captureFunction
local FNAME = R.setmetatable({}, { __mode = "k" })
local CFUNCS = R.setmetatable({}, { __mode = "k" })
local CNAME = R.setmetatable({}, { __mode = "k" })
local THREADP = R.setmetatable({}, { __mode = "k" })

local MKTRAMP = R.loadstring("local impl = ... return function(...) return impl(...) end", "=" .. HARNESS_SRC0)
local TRAMPS = {}
local TRAMP_ENV = nil
local function tramp(impl)
	local t = MKTRAMP(impl)
	if TRAMP_ENV then R.setfenv(t, TRAMP_ENV) else R.insert(TRAMPS, t) end
	return t
end

local function keySuffix(k)
	if isIdent(k) then
		return "." .. k
	end
	return "[" .. fmt(k) .. "]"
end

local ENV

function fmt(v, depth, seen)
	local t = R.type(v)
	if t == "nil" then return "nil" end
	if t == "boolean" then return R.tostring(v) end
	if t == "number" then return fmtNumber(v) end
	if t == "string" then return quote(v) end
	if t == "userdata" then
		if INFO[v] then return tok(v) end
		return "nil --[[userdata]]"
	end
	if t == "function" then
		if FNAME[v] then return FNAME[v] end
		if METHODP_REF and METHODP_REF[v] then return tok(METHODP_REF[v]) end
		return captureFunction(v)
	end
	if t == "table" then
		if v == ENV then return "getfenv()" end
		if GENVNAME[v] then return GENVNAME[v] end
		depth = depth or 0
		seen = seen or {}
		if seen[v] then return "{ --[[cycle]] }" end
		if depth > 6 then return "{ --[[...]] }" end
		seen[v] = true
		local parts = {}
		local n = 0
		for i = 1, 1e9 do
			local x = R.rawget(v, i)
			if x == nil then break end
			n = i
			R.insert(parts, fmt(x, depth + 1, seen))
		end
		local keys = {}
		for k in R.next, v do
			if not (R.type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
				R.insert(keys, k)
			end
		end

		local function rank(k)
			local x = R.rawget(v, k)
			if R.type(x) == "function" then return 4 end
			if k == "Title" or k == "Name" or k == "Text" then return 1 end
			if k == "Desc" or k == "Description" or k == "Content" then return 2 end
			return 3
		end
		R.sort(keys, function(a, b)
			local ta, tb = R.type(a), R.type(b)
			if ta ~= tb then return ta < tb end
			if ta == "string" then
				local ra, rb = rank(a), rank(b)
				if ra ~= rb then return ra < rb end
				return a < b
			end
			if ta == "number" then return a < b end
			return false
		end)
		for _, k in keys do
			local key = isIdent(k) and k or ("[" .. fmt(k, depth + 1, seen) .. "]")
			local x = R.rawget(v, k)

			if k == "Callback" and R.type(x) == "function" then CFG._cbtry = true end
			R.insert(parts, key .. " = " .. fmt(x, depth + 1, seen))
			CFG._cbtry = nil
		end
		seen[v] = nil
		if #parts == 0 then return "{}" end
		local flat = "{ " .. R.concat(parts, ", ") .. " }"
		if #flat <= 100 and not R.find(flat, "\3", 1, true) then return flat end
		local ind = R.rep("\t", depth + 1)
		return "{\n" .. ind .. R.concat(parts, ",\n" .. ind) .. "\n" .. R.rep("\t", depth) .. "}"
	end
	if t == "vector" then
		return "Vector3.new(" .. fmtNumber(v.x) .. ", " .. fmtNumber(v.y) .. ", " .. fmtNumber(v.z) .. ")"
	end
	if t == "buffer" then return "buffer.create(" .. buffer.len(v) .. ")" end
	if t == "thread" and THREADP[v] then return tok(THREADP[v]) end
	return "nil --[[" .. t .. "]]"
end

local function fmtArgs(...)
	local n = R.select("#", ...)
	local parts = {}
	for i = 1, n do
		parts[i] = fmt((R.select(i, ...)))
	end
	return R.concat(parts, ", ")
end

local function globalP(name, tname)
	return newP({ kind = "name", name = name, tname = tname or "Instance" })
end

local function exprP(text, tname, hint)
	return newP({ kind = "expr", text = text, tname = tname or "Instance", hint = hint })
end

local API = { enums = {}, classes = {} }
do
	local src = __ROBLOX or { enums = "", classes = "" }
	for ename, items in string.gmatch(src.enums, "([%w_]+):([^;]*)") do
		local e = { name = ename, items = {}, byName = {}, byValue = {} }
		for iname, v in string.gmatch(items, "([%w_]+)=(%-?%d+)") do
			local item = { Name = iname, Value = R.tonumber(v) }
			R.insert(e.items, item)
			e.byName[iname] = item
			if e.byValue[item.Value] == nil then e.byValue[item.Value] = item end
		end
		API.enums[ename] = e
	end
	for cname, super, fns, evs, props in string.gmatch(src.classes, "([%w_]+)<([%w_]*)|([^|]*)|([^|]*)|([^;]*)") do
		local c = { super = super ~= "" and super or nil, m = {}, e = {}, p = {} }
		for x in string.gmatch(fns, "[^,]+") do c.m[x] = true end
		for x in string.gmatch(evs, "[^,]+") do c.e[x] = true end
		for x in string.gmatch(props, "[^,]+") do
			local name, vt = R.match(x, "^([^:]+):?(.*)$")
			c.p[name] = vt ~= "" and vt or true
		end
		API.classes[cname] = c
	end
end

local function memberKind(cls, k)
	local guard = 0
	while cls and guard < 32 do
		guard += 1
		local c = API.classes[cls]
		if not c then return nil end
		if c.m[k] then return "method" end
		if c.e[k] then return "event" end
		if c.p[k] then return "prop" end
		cls = c.super
	end
	return nil
end

local function propType(cls, k)
	local guard = 0
	while cls and guard < 32 do
		guard += 1
		local c = API.classes[cls]
		if not c then return nil end
		local v = c.p[k]
		if v then return v ~= true and v or nil end
		cls = c.super
	end
	return nil
end

local NUMERIC_T = { float = true, double = true, int = true, int64 = true, int32 = true, int16 = true, number = true }
local NUM_DEFAULT = { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2,
	HipHeight = 2, Gravity = 196.2, FieldOfView = 70, MaxSlopeAngle = 89, TimePosition = 0, Volume = 0.5,
	TimeLength = 1, Speed = 1, Brightness = 1, Range = 16, Size = 1 }
local DT_MEMBERS = {
	Vector3 = { X = "n", Y = "n", Z = "n", Magnitude = "n", Unit = "Vector3" },
	Vector2 = { X = "n", Y = "n", Magnitude = "n", Unit = "Vector2" },
	CFrame = { X = "n", Y = "n", Z = "n", Position = "Vector3", p = "Vector3", LookVector = "Vector3",
		RightVector = "Vector3", UpVector = "Vector3", XVector = "Vector3", YVector = "Vector3", ZVector = "Vector3",
		Rotation = "CFrame" },
	UDim2 = { X = "UDim", Y = "UDim", Width = "UDim", Height = "UDim" },
	UDim = { Scale = "n", Offset = "n" },
	Color3 = { R = "n", G = "n", B = "n" },
	NumberRange = { Min = "n", Max = "n" },
	Rect = { Width = "n", Height = "n", Min = "Vector2", Max = "Vector2" },
}

local PROP_CLASS = {
	LocalPlayer = "Player", Character = "Model", CurrentCamera = "Camera", PlayerGui = "PlayerGui",
	Backpack = "Backpack", PrimaryPart = "Part", HumanoidRootPart = "Part", Head = "Part", Torso = "Part",
	UpperTorso = "MeshPart", LowerTorso = "MeshPart", PlayerScripts = "PlayerScripts", Terrain = "Terrain",
	leaderstats = "Folder", Animator = "Animator",
}

local function childClass(pi, key)
	if R.type(key) ~= "string" then return nil end
	if PROP_CLASS[key] then return PROP_CLASS[key] end
	if pi.className and memberKind(pi.className, key) == "prop" then return nil end
	if API.classes[key] and not API.enums[key] then return key end
	return nil
end

local function indexP(parent, key)
	local pi = INFO[parent]
	local c = pi.children[key]
	if c then return c end
	c = newP({ kind = "index", parent = parent, key = key,
		tname = pi.childT or "Instance",
		hint = R.type(key) == "string" and key or nil, ns = pi.ns,
		className = pi.tname == "Instance" and childClass(pi, key) or nil })
	pi.children[key] = c
	return c
end

local enumRoot
local function enumType(name)
	local c = INFO[enumRoot].children[name]
	if c then return c end
	c = indexP(enumRoot, name)
	INFO[c].tname = "Enum"
	INFO[c].enumName = name
	INFO[c].className = nil
	return c
end
local function enumItem(ename, iname)
	local et = enumType(ename)
	local c = INFO[et].children[iname]
	if c then return c end
	local item = API.enums[ename].byName[iname]
	c = indexP(et, iname)
	local info = INFO[c]
	info.tname = "EnumItem"
	info.enumName = ename
	info.className = nil
	info.props.Name = iname
	info.props.Value = item.Value
	info.props.EnumType = et
	return c
end

local REALV = R.setmetatable({}, { __mode = "k" })

CHAIN.DT_UNSUPPORTED = __ROBLOX and __ROBLOX.datatypes and __ROBLOX.datatypes.UNSUPPORTED
local NOREAL = R.setmetatable({}, { __tostring = function() return "<envlog: no native twin>" end })

local function unwrap(v, depth)
	if isP(v) then
		local r = REALV[v]
		if r == nil then R.error(NOREAL, 0) end
		return r
	elseif R.type(v) == "table" and depth < 3 then
		local t = {}
		for k, x in R.pairs(v) do t[unwrap(k, depth + 1)] = unwrap(x, depth + 1) end
		return t
	elseif R.type(v) == "function" or R.type(v) == "thread" then
		R.error(NOREAL, 0)
	end
	return v
end

local function unwrapArgs(args)
	local ok, out = R.pcall(function()
		local o = { n = args.n }
		for i = 1, args.n do o[i] = unwrap(args[i], 0) end
		return o
	end)
	if ok then return out end
	if out ~= NOREAL then R.error(out, 0) end
	return nil
end

local function realOf(v)
	if isP(v) then return REALV[v], REALV[v] ~= nil end
	if R.type(v) == "table" or R.type(v) == "function" then return nil, false end
	return v, true
end

local PLAIN_T = { number = true, string = true, boolean = true, ["nil"] = true, vector = true }
local function nativeClass(inst)
	return inst:IsA("GuiBase") or inst:IsA("UIBase")
end

local function wrapReal(r, text, hint, depth)
	local t = R.type(r)
	if PLAIN_T[t] then return r, true end
	local tt = R.typeof(r)
	if tt == "userdata" and not NATIVE then tt = __ROBLOX.datatypes.typeOf(r) or tt end
	if tt == "EnumItem" then
		local ename = R.tostring(r.EnumType)
		if API.enums[ename] and API.enums[ename].byName[r.Name] then return enumItem(ename, r.Name), true end
		return nil, false
	end
	if tt == "Instance" or tt == "RBXScriptSignal" or tt == "RBXScriptConnection" or t == "function" or t == "thread" then
		return nil, false
	end
	if t == "table" then
		if (depth or 0) > 2 then return nil, false end
		local out = {}
		for k, x in R.pairs(r) do
			local w, ok = wrapReal(x, text .. "[" .. fmt(k) .. "]", hint, (depth or 0) + 1)
			if not ok then return nil, false end
			out[k] = w
		end
		return out, true
	end
	local p = exprP(text, tt, hint)
	REALV[p] = r
	return p, true
end

local function attachReal(p, libName, k, call, ...)
	local lib
	if NATIVE then
		lib = REAL_G[libName]
	else
		lib = __ROBLOX and __ROBLOX.datatypes and __ROBLOX.datatypes[libName]
		if R.type(lib) ~= "table" then return end
	end
	if lib == nil then return end
	local u = unwrapArgs(table.pack(...))
	if not u then return end
	local ok, r = R.pcall(function()
		local f = lib[k]
		if call then return f(R.unpack(u, 1, u.n)) end
		return f
	end)
	if ok and r ~= nil and R.type(r) ~= "table" then REALV[p] = r end
end

local P2D_LOG = {}
local P2D_MISS = false
local function p2dKey(name, args)
	local parts = { name }
	for i = 1, args.n do
		local a = args[i]
		parts[#parts + 1] = R.type(a) == "number" and R.fmt("%.17g", a) or R.tostring(R.typeof(a))
	end
	return R.concat(parts, "|")
end
local function p2dEncode(v)
	local t = R.typeof(v)
	if t == "number" then return R.fmt("n:%.17g", v) end
	if t == "UDim2" then return R.fmt("u:%.17g,%.17g,%.17g,%.17g", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset) end
	if t == "Vector2" then return R.fmt("v:%.17g,%.17g", v.X, v.Y) end
	if t == "Rect2" then return R.fmt("r:%.17g,%.17g,%.17g,%.17g", v.Min.X, v.Min.Y, v.Size.X, v.Size.Y) end
	if t == "nil" then return "z:" end
	return nil
end
local function p2dDecode(str, text)
	local kind, rest = R.match(str, "^(%a):(.*)$")
	if kind == "n" then return R.tonumber(rest) end
	if kind == "z" then return nil end
	local nums = {}
	for x in string.gmatch(rest, "[^,]+") do nums[#nums + 1] = R.tonumber(x) end
	if kind == "u" then
		local p = exprP(text, "UDim2", "position")
		local xs = exprP(text .. ".X", "UDim", "X")
		INFO[xs].props.Scale, INFO[xs].props.Offset = nums[1], nums[2]
		local ys = exprP(text .. ".Y", "UDim", "Y")
		INFO[ys].props.Scale, INFO[ys].props.Offset = nums[3], nums[4]
		INFO[p].props.X, INFO[p].props.Y = xs, ys
		INFO[p].props.Width, INFO[p].props.Height = xs, ys
		return p
	end
	if kind == "v" then
		local p = exprP(text, "Vector2", "vector")
		INFO[p].props.X, INFO[p].props.Y = nums[1], nums[2]
		INFO[p].props.Magnitude = math.sqrt(nums[1] * nums[1] + nums[2] * nums[2])
		return p
	end
	if kind == "r" then

		local p = exprP(text, "Rect2", "rect")
		local lo = exprP(text .. ".Min", "Vector2", "vector")
		INFO[lo].props.X, INFO[lo].props.Y = nums[1], nums[2]
		local sz = exprP(text .. ".Size", "Vector2", "vector")
		INFO[sz].props.X, INFO[sz].props.Y = nums[3], nums[4]
		INFO[p].props.Min, INFO[p].props.Size = lo, sz
		return p
	end
	return nil
end

local function callP(text, hint, tname, force)
	local p = newP({ kind = "call", tname = tname or "Instance", hint = hint })
	local st = emit({ call = text, res = p })
	INFO[p].stmt = st
	if force then INFO[p].forceVar = true end
	return p
end

local FUNCS = {}
local FREC = {}
local nextFid = 0
local captureDepth = 0
local paramCounter = {}

local function paramName(base)
	paramCounter[base] = (paramCounter[base] or 0) + 1
	local n = paramCounter[base]
	return n == 1 and base or (base .. n)
end

local popTo

local lastThread = nil

local function runInBlock(block, fn, ...)
	block.isRoot = true
	R.insert(STACK, block)
	local level = #STACK
	captureDepth += 1
	local th = R.type(fn) == "thread" and fn or coroutine.create(fn)
	lastThread = th
	local res = table.pack(coroutine.resume(th, ...))
	if res[1] and res[2] == ABORT and coroutine.status(th) == "suspended" then res = { false, ABORT, n = 2 } end
	captureDepth -= 1
	popTo(level - 1)
	if not res[1] then
		local err = res[2]
		if err == ABORT then
			R.insert(block.lines, { text = "-- [envlog] trace budget ran out here: " .. R.tostring(ABORT_REASON) })
			R.error(ABORT, 0)
		elseif err == TAMPER then
			if CFG.debug_tamper then R.print("[tamper-in-block]", debug.traceback()) end
			R.insert(block.lines, { text = "-- [envlog] Luraph integrity-check thread (anti-tamper) suppressed here" })
		elseif err ~= LOOP then
			R.insert(block.lines, { text = "-- [envlog] error: " .. R.gsub(R.tostring(err), "\n", " ") })
		end
	end
	return res
end

local DEFERRED = {}

local HANDLERS = {}

function captureFunction(fn, names, args, defer)
	local fid = FUNCS[fn]
	if fid and not defer then return "\3" .. fid .. "\4" end
	nextFid += 1
	fid = nextFid
	FUNCS[fn] = fid
	local rec = { params = {}, block = { lines = {}, waits = {} } }
	FREC[fid] = rec
	if captureDepth >= MAX_DEPTH then
		R.insert(rec.block.lines, { text = "-- [envlog] nesting too deep" })
		return "\3" .. fid .. "\4"
	end
	local callArgs = {}
	if args then
		callArgs = args
		rec.params = { "..." }
	else
		names = names or { "...", "..." }
		local vararg = names[1] == "..."
		for i, nm in names do
			local pn = vararg and paramName("arg") or paramName(nm)
			rec.params[i] = pn
			callArgs[i] = newP({ kind = "name", gen = true, name = pn, tname = "Instance" })
		end
	end
	if defer == "handler" then
		R.insert(HANDLERS, { rec = rec, fn = fn, args = callArgs, n = args and args.n or #callArgs })
		return "\3" .. fid .. "\4"
	end
	if defer then

		local th = coroutine.create(fn)
		lastThread = th
		R.insert(DEFERRED, { rec = rec, thread = th, args = callArgs, n = args and args.n or #callArgs, due = defer })
		return "\3" .. fid .. "\4"
	end
	local tryAlt = CFG._cbtry and not args
	CFG._cbtry = nil
	local res = runInBlock(rec.block, fn, R.unpack(callArgs, 1, args and args.n or #callArgs))

	if tryAlt and res[1] and #callArgs >= 1 then
		local alt = { lines = {}, waits = {} }
		local r2 = runInBlock(alt, fn, false, R.unpack(callArgs, 2, #callArgs))
		local clean = r2[1]
		for _, s in alt.lines do
			if s.text and R.find(s.text, "-- [envlog]", 1, true) then clean = false end
		end
		if clean then
			rec.alt = alt
			local pn = "state"
			INFO[callArgs[1]].name = pn
			rec.params[1] = pn
		end
	end
	return "\3" .. fid .. "\4"
end

local function runHandlers()
	local i = 1
	while i <= #HANDLERS do
		local h = HANDLERS[i]
		i += 1
		popTo(1)
		local ok, err = R.pcall(runInBlock, h.rec.block, h.fn, R.unpack(h.args, 1, h.n))
		if not ok and err == ABORT then return end
	end
end

local function runDeferred()
	while #DEFERRED > 0 do
		table.sort(DEFERRED, function(a, b) return a.due < b.due end)
		local d = R.remove(DEFERRED, 1)
		if coroutine.status(d.thread) == "suspended" then
			local ok, err = R.pcall(runInBlock, d.rec.block, d.thread, R.unpack(d.args, 1, d.n))
			if not ok and err == ABORT then return end
		else
			R.insert(d.rec.block.lines, { text = "-- [envlog] cancelled before it ran" })
		end
	end
end

function popTo(level)
	while #STACK > level do
		local b = STACK[#STACK]
		STACK[#STACK] = nil
		if b.onClose then b.onClose() end
	end
end

local function iterProxy(p, how)
	local state = 0
	local kp, vp
	return function()
		state += 1
		if state == 1 then
			local b = { lines = {}, waits = {} }
			kp = newP({ kind = "name", gen = true, name = paramName(how == "ipairs" and "i" or "k"), tname = "number" })
			vp = newP({ kind = "name", gen = true, name = paramName("v"), tname = "Instance" })
			local header = "for " .. tok(kp) .. ", " .. tok(vp) .. " in " ..
				(how and (how .. "(" .. tok(p) .. ")") or tok(p)) .. " do"
			emit({ header = header, block = b })
			R.insert(STACK, b)
			b.level = #STACK
			return kp, vp
		end

		for i = #STACK, 1, -1 do
			if STACK[i].level == i and STACK[i].header == nil then

			end
		end
		popTo(#STACK - 1)
		return nil
	end
end

local function normalize(block, from, to, baseId, baseFid)
	local parts = {}
	for i = from, to do
		local s = block.lines[i]
		local text = s.text or s.call or s.header or ""
		text = R.gsub(text, "\1(%d+)\2", function(id)
			id = R.tonumber(id)
			return id >= baseId and ("\1r" .. (id - baseId) .. "\2") or nil
		end)
		text = R.gsub(text, "\3(%d+)\4", function(id)
			id = R.tonumber(id)
			return id >= baseFid and ("\3r" .. (id - baseFid) .. "\4") or nil
		end)
		parts[#parts + 1] = text
	end
	return R.concat(parts, "\n")
end

local function onWait()
	local b = curBlock()
	local w = b.waits
	R.insert(w, { line = #b.lines, id = nextId, fid = nextFid })
	local n = #w
	if n >= 3 then
		local a, m, c = w[n - 2], w[n - 1], w[n]
		if c.line - m.line == m.line - a.line then
			local s1 = normalize(b, a.line + 1, m.line, a.id, a.fid)
			local s2 = normalize(b, m.line + 1, c.line, m.id, m.fid)
			if s1 == s2 then
				for _ = m.line + 1, c.line do
					R.remove(b.lines)
				end
				R.insert(b.lines, { text = "-- [envlog] the statements above repeat forever (loop)" })
				b.stopped = 0
				R.error(LOOP, 0)
			end
		end
	end

	local root, rootLevel = nil, 1
	for i = #STACK, 1, -1 do
		if STACK[i].isRoot or i == 1 then root, rootLevel = STACK[i], i; break end
	end
	root.tape = root.tape or {}
	root.marks = root.marks or {}
	local marks = root.marks
	R.insert(marks, { pos = #root.tape, id = nextId, fid = nextFid, depth = #STACK, block = b })
	local nm = #marks
	if nm >= 3 then
		local m1, m2, m3 = marks[nm - 2], marks[nm - 1], marks[nm]
		local k = m2.pos - m1.pos
		if CFG.debug_loops then R.print("[loop marks]", m1.pos, m2.pos, m3.pos, m1.depth, m2.depth, m3.depth) end
		if k > 0 and m3.pos - m2.pos == k and m3.depth > m2.depth then
			local function seg(from, to, baseId, baseFid)

				local order, n = {}, 0
				local function path(q, d)
					local qi = q and INFO[q]
					if not qi or d > 12 then return "?" end
					if qi.kind == "name" and not qi.gen then return qi.name or "?" end
					if qi.kind == "index" and qi.parent then return path(qi.parent, d + 1) .. "." .. R.tostring(qi.key) end
					if not order[q] then n += 1; order[q] = n end
					return "#" .. order[q]
				end
				local parts = {}
				for i = from, to do
					local st = root.tape[i].stmt
					local text = st.text or st.call or st.header or ""
					if st.res and isP(st.res) then text = text .. " ->" .. path(st.res, 0) end
					text = R.gsub(text, "\1(%d+)\2", function(id)
						return "\1" .. path(BYID[R.tonumber(id)], 0) .. "\2"
					end)
					text = R.gsub(text, "\3(%d+)\4", function(id)
						id = R.tonumber(id)
						return id >= baseFid and ("\3r" .. (id - baseFid) .. "\4") or nil
					end)
					parts[#parts + 1] = text
				end
				return R.concat(parts, "\n")
			end
			local sA, sB = seg(m1.pos + 1, m2.pos, m1.id, m1.fid), seg(m2.pos + 1, m3.pos, m2.id, m2.fid)
			if CFG.debug_loops and sA ~= sB then R.print("[loop A]\n" .. sA .. "\n[loop B]\n" .. sB) end
			if sA == sB then

				for i = m3.pos, m2.pos + 1, -1 do
					local e = root.tape[i]
					if e.block.lines[#e.block.lines] == e.stmt then R.remove(e.block.lines) end
					root.tape[i] = nil
				end

				popTo(m1.depth)
				local home = curBlock()

				local w = root.tape[m2.pos]
				if w and w.block ~= home and w.block.lines[#w.block.lines] == w.stmt then
					R.remove(w.block.lines)
					R.insert(home.lines, w.stmt)
				end
				R.insert(home.lines, { text = "-- [envlog] the statements above repeat forever (loop)" })
				home.stopped = 0
				R.error(LOOP, 0)
			end
		end
	end
	if n > MAX_WAITS then
		R.insert(b.lines, { text = "-- [envlog] stopped after " .. MAX_WAITS .. " waits" })
		b.stopped = 0
		R.error(LOOP, 0)
	end
end

local DATATYPES = {
	Vector3 = 1, Vector2 = 1, Vector3int16 = 1, Vector2int16 = 1, CFrame = 1, Color3 = 1,
	UDim = 1, UDim2 = 1, BrickColor = 1, TweenInfo = 1, NumberRange = 1, NumberSequence = 1,
	NumberSequenceKeypoint = 1, ColorSequence = 1, ColorSequenceKeypoint = 1, Ray = 1,
	Rect = 1, Region3 = 1, Region3int16 = 1, PhysicalProperties = 1, Font = 1,
	DateTime = 1, Axes = 1, Faces = 1, PathWaypoint = 1, SharedTable = 1, OverlapParams = 1,
	RaycastParams = 1, CatalogSearchParams = 1, DockWidgetPluginGuiInfo = 1, Path2DControlPoint = 1,
	Content = 1, SecurityCapabilities = 1, FloatCurveKey = 1, RotationCurveKey = 1, ValueCurveKey = 1,
	CFrameCurveKey = 1, UniqueId = 1,
}

local SIGNAL_PARAMS = {
	PlayerAdded = { "player" }, PlayerRemoving = { "player" },
	CharacterAdded = { "character" }, CharacterRemoving = { "character" }, CharacterAppearanceLoaded = { "character" },
	Touched = { "hit" }, TouchEnded = { "hit" },
	InputBegan = { "input", "gameProcessed" }, InputEnded = { "input", "gameProcessed" },
	InputChanged = { "input", "gameProcessed" },
	Heartbeat = { "deltaTime" }, RenderStepped = { "deltaTime" }, PreSimulation = { "deltaTime" },
	PostSimulation = { "deltaTime" }, PreRender = { "deltaTime" }, Stepped = { "time", "deltaTime" },
	ChildAdded = { "child" }, ChildRemoved = { "child" },
	DescendantAdded = { "descendant" }, DescendantRemoving = { "descendant" },
	Changed = { "value" }, HealthChanged = { "health" }, Chatted = { "message" },
	FocusLost = { "enterPressed", "inputObject" }, Triggered = { "player" },
	PromptTriggered = { "prompt", "player" }, PromptButtonHoldBegan = { "prompt", "player" },
	Idled = { "idleTime" }, MouseButton1Click = {}, MouseButton1Down = { "x", "y" },
	Activated = { "inputObject", "clickCount" }, Died = {}, Event = { "..." },
	OnClientEvent = { "..." }, OnClientInvoke = { "..." }, OnInvoke = { "..." },
	AncestryChanged = { "child", "parent" }, AttributeChanged = { "attribute" },
	StateChanged = { "old", "new" }, MoveToFinished = { "reached" }, Completed = { "playbackState" },
}

local CLASS_HINT = {
	GetChildren = "children", GetDescendants = "descendants", GetPlayers = "players",
	GetTouchingParts = "parts", GetPartsInPart = "parts", GetPartBoundsInBox = "parts",
	GetPartBoundsInRadius = "parts", GetTagged = "tagged", GetAttributes = "attributes",
	GetPlayingAnimationTracks = "tracks", GetConnectedParts = "parts", GetJoints = "joints",
	GetChildrenOfClass = "children",
}

for k, v in {
	JSONEncode = "json", JSONDecode = "data", HttpGet = "response", HttpGetAsync = "response",
	GetAsync = "response", PostAsync = "response", RequestAsync = "response",
	Inverse = "inverse", ToWorldSpace = "cframe", ToObjectSpace = "cframe",
	Raycast = "raycastResult", GetMouse = "mouse", LoadAnimation = "track",
	InvokeServer = "response", Clone = "clone",
	GetPropertyChangedSignal = "changedSignal", GetAttribute = "attribute",
	GenerateGUID = "guid", UrlEncode = "encoded", Notify = "notification",
} do
	CLASS_HINT[k] = v
end

for _, n in { "Window", "Tab", "Section", "Toggle", "Button", "Slider", "Dropdown", "Input",
	"Keybind", "Colorpicker", "Paragraph", "Dialog", "Label", "Textbox", "Divider", "Popup",
	"Code", "Group", "Page", "Category", "Checkbox", "ColorPicker", "TextBox" } do
	CLASS_HINT[n] = n
end

local serviceCache = {}
local GAMEP
local WORKSPACEP
local urls = {}
local remotes = {}

local function methodName(info)
	if info.kind == "index" and R.type(info.key) == "string" then return info.key end
	return nil
end

local function remember(list, v)
	if not list[v] then
		list[v] = true
		R.insert(list, v)
	end
end

local function instName(p)
	local v = INFO[p].props.Name
	if R.type(v) == "string" then return v end
	return INFO[p].className or "Instance"
end
local function kidsOf(p)
	local info = INFO[p]
	info.kids = info.kids or {}
	return info.kids
end
local function setParent(child, parent)
	local ci = INFO[child]
	local old = ci.props.Parent
	if isP(old) then
		local list = kidsOf(old)
		for i = #list, 1, -1 do
			if list[i] == child then R.remove(list, i) end
		end
	end
	if isP(parent) then R.insert(kidsOf(parent), child) end
	ci.props.Parent = parent
	local rc = REALV[child]
	if rc ~= nil and R.typeof(rc) == "Instance" then
		local rp = isP(parent) and REALV[parent] or nil
		R.pcall(function() rc.Parent = (R.typeof(rp) == "Instance") and rp or nil end)
	end
end
local function findKid(p, name, recursive)
	for _, c in kidsOf(p) do
		if instName(c) == name then return c end
	end
	if recursive then
		for _, c in kidsOf(p) do
			local r = findKid(c, name, true)
			if r then return r end
		end
	end
	return nil
end
local function descendants(p, out)
	for _, c in kidsOf(p) do
		R.insert(out, c)
		descendants(c, out)
	end
	return out
end
local function destroyInst(p)
	local info = INFO[p]
	if info.destroyed then return end
	for _, c in table.clone(kidsOf(p)) do destroyInst(c) end
	if isP(info.props.Parent) then setParent(p, nil) end
	info.props.Parent = nil
	info.destroyed = true
	local r = REALV[p]
	if r ~= nil and R.typeof(r) == "Instance" then R.pcall(r.Destroy, r) end
end
local RUNSERVICE_BOOL = { IsStudio = false, IsServer = false, IsClient = true, IsRunning = true,
	IsRunMode = false, IsEdit = false }

local NO_NATIVE_METHOD = { Clone = 1, Destroy = 1, Remove = 1, GetChildren = 1, GetDescendants = 1,
	FindFirstChild = 1, WaitForChild = 1, FindFirstChildOfClass = 1, FindFirstChildWhichIsA = 1,
	FindFirstAncestor = 1, FindFirstAncestorOfClass = 1, FindFirstAncestorWhichIsA = 1, FindFirstDescendant = 1,
	ClearAllChildren = 1, IsA = 1, Connect = 1, Once = 1, Wait = 1, GetPropertyChangedSignal = 1,
	GetAttributeChangedSignal = 1, IsDescendantOf = 1, IsAncestorOf = 1, GetFullName = 1 }

do
	local FB = buffer.create(4)
	local function f32(x)
		buffer.writef32(FB, 0, x)
		return buffer.readf32(FB, 0)
	end
	local M = {}
	CHAIN.p2d = M
	M.f32 = f32

	local function num(x)
		if R.type(x) == "number" then return x end
		return 0
	end

	function M.udim2(p)
		if not isP(p) then return nil end
		local inf = INFO[p]
		local c = inf.ctor
		if c and c.ns == "UDim2" then
			local a = c.args
			if c.fn == "new" then
				if isP(a[1]) or isP(a[2]) then
					local x, y = INFO[a[1]] and INFO[a[1]].ctor, INFO[a[2]] and INFO[a[2]].ctor
					return { x and num(x.args[1]) or 0, x and num(x.args[2]) or 0, y and num(y.args[1]) or 0,
						y and num(y.args[2]) or 0 }
				end
				return { num(a[1]), num(a[2]), num(a[3]), num(a[4]) }
			elseif c.fn == "fromScale" then
				return { num(a[1]), 0, num(a[2]), 0 }
			elseif c.fn == "fromOffset" then
				return { 0, num(a[1]), 0, num(a[2]) }
			end
			return nil
		end
		local X, Y = inf.props and inf.props.X, inf.props and inf.props.Y
		if isP(X) and isP(Y) then
			local xp, yp = INFO[X].props, INFO[Y].props
			return { num(xp.Scale), num(xp.Offset), num(yp.Scale), num(yp.Offset) }
		end
		return nil
	end

	function M.frameSize(path)
		local parent = INFO[path].props and INFO[path].props.Parent
		if not isP(parent) then return nil end
		local sz = INFO[parent].props and INFO[parent].props.Size
		local u = sz and M.udim2(sz)
		if not u then return nil end
		if u[1] ~= 0 or u[3] ~= 0 then return nil end
		return u[2], u[4]
	end
	local function resolve(u, W, H)
		return f32(f32(u[1] * W) + u[2]), f32(f32(u[3] * H) + u[4])
	end

	function M.segments(cps, W, H)
		local pts = {}
		for i, cp in R.ipairs(cps) do
			local c = isP(cp) and INFO[cp].ctor
			if not c or c.ns ~= "Path2DControlPoint" then return nil end
			local zero = { 0, 0, 0, 0 }
			local pos = c.args.n >= 1 and M.udim2(c.args[1]) or zero
			local left = c.args.n >= 2 and M.udim2(c.args[2]) or zero
			local right = c.args.n >= 3 and M.udim2(c.args[3]) or zero
			if not pos or not left or not right then return nil end
			local px, py = resolve(pos, W, H)
			local lx, ly = resolve(left, W, H)
			local rx, ry = resolve(right, W, H)
			pts[i] = { px, py, lx, ly, rx, ry }
		end
		local segs = {}

		local hx0, hy0, hx1, hy1
		for i = 1, #pts do
			local p = pts[i]
			for k = 1, 6, 2 do
				local x, y = p[k], p[k + 1]
				if k > 2 then

					if k == 3 then x, y = p[1] + p[3], p[2] + p[4]
					else x, y = p[1] + p[5], p[2] + p[6] end
				end
				if not hx0 then hx0, hy0, hx1, hy1 = x, y, x, y
				else
					if x < hx0 then hx0 = x end
					if y < hy0 then hy0 = y end
					if x > hx1 then hx1 = x end
					if y > hy1 then hy1 = y end
				end
			end
		end
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local s = { a[1], a[2] }
			if a[5] ~= 0 or a[6] ~= 0 then
				R.insert(s, f32(a[1] + a[5])); R.insert(s, f32(a[2] + a[6]))
			end
			if b[3] ~= 0 or b[4] ~= 0 then
				R.insert(s, f32(b[1] + b[3])); R.insert(s, f32(b[2] + b[4]))
			end
			R.insert(s, b[1]); R.insert(s, b[2])
			segs[i] = M.coeffs(s)
		end
		if hx0 then segs.hull = { hx0, hy0, hx1, hy1 } end
		return segs
	end

	function M.coeffs(s)
		local n = #s // 2
		local x0, y0 = s[1], s[2]
		local c = { n = n, x0 = x0, y0 = y0 }
		if n == 2 then
			c.c1x, c.c1y = f32(s[3] - x0), f32(s[4] - y0)
		elseif n == 3 then
			local x1, y1, x2, y2 = s[3], s[4], s[5], s[6]
			c.c1x, c.c1y = f32(f32(x1 - x0) * 2), f32(f32(y1 - y0) * 2)
			c.c2x, c.c2y = f32(f32(x0 - f32(x1 * 2)) + x2), f32(f32(y0 - f32(y1 * 2)) + y2)
		else
			local x1, y1, x2, y2, x3, y3 = s[3], s[4], s[5], s[6], s[7], s[8]
			c.c1x, c.c1y = f32(f32(x1 - x0) * 3), f32(f32(y1 - y0) * 3)
			c.c2x = f32(f32(f32(x0 - f32(x1 * 2)) + x2) * 3)
			c.c2y = f32(f32(f32(y0 - f32(y1 * 2)) + y2) * 3)
			c.c3x = f32(f32(f32(x3 - x0) + f32(x1 * 3)) - f32(x2 * 3))
			c.c3y = f32(f32(f32(y3 - y0) + f32(y1 * 3)) - f32(y2 * 3))
		end
		return c
	end
	function M.eval(c, u)
		if c.n == 2 then
			return f32(c.x0 + f32(c.c1x * u)), f32(c.y0 + f32(c.c1y * u))
		elseif c.n == 3 then
			return f32(c.x0 + f32(f32(c.c1x + f32(c.c2x * u)) * u)), f32(c.y0 + f32(f32(c.c1y + f32(c.c2y * u)) * u))
		end
		local ix, iy = f32(c.c2x + f32(c.c3x * u)), f32(c.c2y + f32(c.c3y * u))
		return f32(c.x0 + f32(f32(c.c1x + f32(ix * u)) * u)), f32(c.y0 + f32(f32(c.c1y + f32(iy * u)) * u))
	end
	function M.tangent(c, u)
		if c.n == 2 then return c.c1x, c.c1y end
		if c.n == 3 then
			local k = f32(u * 2)
			return f32(c.c1x + f32(c.c2x * k)), f32(c.c1y + f32(c.c2y * k))
		end
		local k = f32(3 * u)
		return f32(c.c1x + f32(u * f32(f32(c.c2x * 2) + f32(c.c3x * k)))),
			f32(c.c1y + f32(u * f32(f32(c.c2y * 2) + f32(c.c3y * k))))
	end
	local function dist(ax, ay, bx, by)
		local dx, dy = f32(bx - ax), f32(by - ay)
		return f32(math.sqrt(f32(f32(dx * dx) + f32(dy * dy))))
	end
	M.dist = dist
	local TOL = f32(1e-5)

	function M.eval0(c, u)
		if c.n == 2 then
			return f32(c.c1x * u), f32(c.c1y * u)
		elseif c.n == 3 then
			return f32(f32(c.c1x + f32(c.c2x * u)) * u), f32(f32(c.c1y + f32(c.c2y * u)) * u)
		end
		local ix, iy = f32(c.c2x + f32(c.c3x * u)), f32(c.c2y + f32(c.c3y * u))
		return f32(f32(c.c1x + f32(ix * u)) * u), f32(f32(c.c1y + f32(iy * u)) * u)
	end
	function M.seglen(c)
		local function rec(t0, t1, x0, y0, x1, y1, depth)
			local tm = f32(f32(t0 + t1) * 0.5)
			local xm, ym = M.eval0(c, tm)
			local a = dist(x0, y0, x1, y1)
			local b = f32(dist(x0, y0, xm, ym) + dist(xm, ym, x1, y1))
			if depth >= 30 or f32(b - a) < TOL then return b end
			return f32(rec(t0, tm, x0, y0, xm, ym, depth + 1) + rec(tm, t1, xm, ym, x1, y1, depth + 1))
		end
		local x0, y0 = M.eval0(c, 0)
		local x1, y1 = M.eval0(c, 1)
		return rec(0, 1, x0, y0, x1, y1, 0)
	end

	local SIXTH = f32(1 / 6)
	function M.arcU(c, s)
		local d2x, d2y = f32(c.c2x * 2), f32(c.c2y * 2)
		local d3x, d3y
		if c.n == 4 then d3x, d3y = f32(c.c3x * 3), f32(c.c3y * 3) end
		local function inv(u)
			local dx, dy
			if c.n == 3 then
				dx, dy = f32(c.c1x + f32(d2x * u)), f32(c.c1y + f32(d2y * u))
			else
				dx = f32(c.c1x + f32(u * f32(d2x + f32(u * d3x))))
				dy = f32(c.c1y + f32(u * f32(d2y + f32(u * d3y))))
			end
			return math.sqrt(f32(f32(dx * dx) + f32(dy * dy)))
		end
		local h = f32(s / 32)
		local u = 0
		for _ = 1, 32 do
			local k1 = f32(h / f32(inv(u)))
			local k2 = f32(h / f32(inv(f32(u + f32(k1 * 0.5)))))
			local k3 = f32(h / f32(inv(f32(u + f32(k2 * 0.5)))))
			local k4 = f32(h / f32(inv(f32(u + k3))))
			u = f32(u + f32(f32(f32(k1 + f32(2 * f32(k2 + k3))) + k4) * SIXTH))
		end
		return u
	end
	function M.length(segs)
		local t = 0
		for _, c in R.ipairs(segs) do
			c.len = c.len or M.seglen(c)
			t = f32(t + c.len)
		end
		return t
	end

	function M.locate(segs, t)
		t = f32(t)
		if t < 0 then t = 0 elseif t > 1 then t = 1 end
		local n = #segs
		local x = f32(t * n)
		local k = math.min(math.floor(x), n - 1)
		return segs[k + 1], f32(x - k)
	end

	function M.locateArc(segs, t)
		t = f32(t)
		if t < 0 then t = 0 elseif t > 1 then t = 1 end
		local L = M.length(segs)
		local s = f32(t * L)

		for _, c in R.ipairs(segs) do
			if s <= c.len then
				if c.n == 2 then return c, f32(s / c.len) end
				return c, M.arcU(c, s)
			end
			s = f32(s - c.len)
		end
		return segs[1], 0
	end

	function M.refresh(path)
		local inf = INFO[path]
		local W, H = M.frameSize(path)
		if not (W and H) then return inf.p2dSegs end

		if inf.p2dSegs and inf.p2dW == W and inf.p2dH == H then return inf.p2dSegs end
		local pts = inf.p2dPoints
		if not pts then return inf.p2dSegs end
		local ok, segs = R.pcall(M.segments, pts, W, H)
		if not ok or type(segs) ~= "table" then return inf.p2dSegs end
		inf.p2dSegs, inf.p2dW, inf.p2dH = segs, W, H
		return segs
	end

	function M.answer(path, name, t)
		local inf = INFO[path]

		local segs = M.refresh(path)
		if not segs then return nil end

		if name == "GetBoundingRect" then
			local h = segs.hull
			if not h then return nil end
			local W, H = inf.p2dW, inf.p2dH
			if not (W and H) or W == 0 or H == 0 then return nil end
			return R.fmt("r:%.17g,%.17g,%.17g,%.17g",
				f32(h[1] / W), f32(h[2] / H), f32((h[3] - h[1]) / W), f32((h[4] - h[2]) / H))
		end
		local W, H = inf.p2dW, inf.p2dH
		if name == "GetLength" then
			return R.fmt("n:%.17g", #segs > 0 and M.length(segs) or 0)
		end

		if #segs == 0 then return nil end
		if R.type(t) ~= "number" then return nil end
		local c, u
		if name == "GetPositionOnCurve" or name == "GetTangentOnCurve" then
			c, u = M.locate(segs, t)
		elseif name == "GetPositionOnCurveArcLength" or name == "GetTangentOnCurveArcLength" then
			c, u = M.locateArc(segs, t)
		end
		if not c then return nil end
		if R.find(name, "Position", 1, true) then
			local x, y = M.eval(c, u)
			return R.fmt("u:%.17g,0,%.17g,0", f32(x / W), f32(y / H))
		end
		local x, y = M.tangent(c, u)
		return R.fmt("v:%.17g,%.17g", x, y)
	end
end

do
	local function isGuiObject(p)
		if not isP(p) then return false end
		local cls = INFO[p].className
		if not cls then return false end
		return cls == "Frame" or cls == "TextButton" or cls == "TextLabel"
			or cls == "ImageButton" or cls == "ImageLabel" or cls == "TextBox"
			or cls == "ScrollingFrame" or cls == "ViewportFrame" or cls == "CanvasGroup"
			or cls == "VideoFrame" or cls == "GuiObject" or cls == "GuiButton" or cls == "GuiLabel"
	end

	local function getGuiParent(p)
		local par = INFO[p] and INFO[p].props and INFO[p].props.Parent
		if isP(par) then return par end
		return nil
	end

	local function getUDim2Vals(v)
		if R.typeof(v) == "UDim2" then return v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset end
		if isP(v) then
			local u = CHAIN.p2d and CHAIN.p2d.udim2(v)
			if u then return u[1], u[2], u[3], u[4] end
		end
		return 0, 0, 0, 0
	end

	local function getVec2Vals(v)
		if R.typeof(v) == "Vector2" then return v.X, v.Y end
		if isP(v) then
			local inf = INFO[v]
			if inf and inf.ctor and inf.ctor.ns == "Vector2" then
				local a = inf.ctor.args
				return (R.tonumber(a[1]) or 0), (R.tonumber(a[2]) or 0)
			end
			if inf and inf.props and inf.props.X ~= nil and inf.props.Y ~= nil then
				return (R.tonumber(inf.props.X) or 0), (R.tonumber(inf.props.Y) or 0)
			end
		end
		return 0, 0
	end

	local function clampVal(v, lo, hi)
		if v < lo then return lo elseif v > hi then return hi else return v end
	end

	local function getUDimVals(v)
		if R.typeof(v) == "UDim" then return v.Scale, v.Offset end
		if isP(v) then
			local inf = INFO[v]
			if inf and inf.props and (inf.props.Scale ~= nil or inf.props.Offset ~= nil) then
				return (R.tonumber(inf.props.Scale) or 0), (R.tonumber(inf.props.Offset) or 0)
			end
			if inf and inf.ctor and inf.ctor.args then
				return (R.tonumber(inf.ctor.args[1]) or 0), (R.tonumber(inf.ctor.args[2]) or 0)
			end
		end
		return 0, 0
	end

	local function getAncestorScale(p)
		local sc = 1
		local cur = getGuiParent(p)
		while cur and isP(cur) do
			local kids = kidsOf(cur)
			for _, kid in R.ipairs(kids) do
				if INFO[kid] and INFO[kid].className == "UIScale" then
					local s = R.tonumber(INFO[kid].props.Scale) or 1
					sc = sc * s
				end
			end
			cur = getGuiParent(cur)
		end
		return sc
	end

	local function getOwnScale(p)
		if not isP(p) then return 1 end
		local kids = kidsOf(p)
		for _, kid in R.ipairs(kids) do
			if INFO[kid] and INFO[kid].className == "UIScale" then
				return R.tonumber(INFO[kid].props.Scale) or 1
			end
		end
		return 1
	end

	local computeAbsoluteSize, computeAbsolutePosition

	local function getParentLayout(p)
		local par = getGuiParent(p)
		if not par or not isP(par) or not isGuiObject(par) then
			return 0, 0, 1920, 1080, 1
		end
		local parX, parY = computeAbsolutePosition(par)
		local parW, parH = computeAbsoluteSize(par)
		local parScale = getAncestorScale(par) * getOwnScale(par)

		local padL, padR, padT, padB = 0, 0, 0, 0
		local kids = kidsOf(par)
		for _, kid in R.ipairs(kids) do
			if INFO[kid] and INFO[kid].className == "UIPadding" then
				local props = INFO[kid].props
				local plS, plO = getUDimVals(props.PaddingLeft)
				local prS, prO = getUDimVals(props.PaddingRight)
				local ptS, ptO = getUDimVals(props.PaddingTop)
				local pbS, pbO = getUDimVals(props.PaddingBottom)
				padL = plS * parW + plO * parScale
				padR = prS * parW + prO * parScale
				padT = ptS * parH + ptO * parScale
				padB = pbS * parH + pbO * parScale
				break
			end
		end

		return parX + padL, parY + padT, parW - padL - padR, parH - padT - padB, parScale
	end

	function computeAbsoluteSize(p)
		if not isP(p) then return 0, 0 end
		local cls = INFO[p].className
		if cls == "ScreenGui" or cls == "GuiMain" then
			return 1920, 1080
		end
		if not isGuiObject(p) then return 0, 0 end

		local _, _, availW, availH, parScale = getParentLayout(p)
		local sx, ox, sy, oy = getUDim2Vals(INFO[p].props.Size)
		local w = sx * availW + ox * parScale
		local h = sy * availH + oy * parScale

		local kids = kidsOf(p)
		for _, kid in R.ipairs(kids) do
			if INFO[kid] and INFO[kid].className == "UISizeConstraint" then
				local minX, minY = getVec2Vals(INFO[kid].props.MinSize)
				local maxX, maxY = getVec2Vals(INFO[kid].props.MaxSize)
				if maxX == 0 and maxY == 0 then maxX, maxY = 1e9, 1e9 end
				w = clampVal(w, minX, maxX)
				h = clampVal(h, minY, maxY)
				break
			end
		end

		local ownSc = getOwnScale(p)
		w = w * ownSc
		h = h * ownSc

		return w, h
	end

	function computeAbsolutePosition(p)
		if not isP(p) then return 0, 0 end
		local cls = INFO[p].className
		if cls == "ScreenGui" or cls == "GuiMain" then
			return 0, 0
		end
		if not isGuiObject(p) then return 0, 0 end

		local origX, origY, availW, availH, parScale = getParentLayout(p)
		local sx, ox, sy, oy = getUDim2Vals(INFO[p].props.Position)
		local curW, curH = computeAbsoluteSize(p)
		local apX, apY = getVec2Vals(INFO[p].props.AnchorPoint)

		local x = origX + sx * availW + ox * parScale - apX * curW
		local y = origY + sy * availH + oy * parScale - apY * curH

		return x, y
	end

	CHAIN.isGuiObject = isGuiObject
	CHAIN.computeAbsoluteSize = computeAbsoluteSize
	CHAIN.computeAbsolutePosition = computeAbsolutePosition
end

local function onCall(p, ...)
	checkBudget()
	local info = INFO[p]
	if CFG.ptrace then
		local a2 = R.select(2, ...)
		R.print("[call]", info.name or info.hint or info.key, R.select("#", ...), R.type(a2) == "string" and a2 or "")
	end
	local n = R.select("#", ...)
	local first = ...
	local name = methodName(info)
	local isMethod = info.kind == "index" and n >= 1 and first == info.parent and isP(first)
	local calleeText
	local args
	if isMethod then
		calleeText = tok(info.parent) .. ":" .. (isIdent(name) and name or "__call")
		args = table.pack(R.select(2, ...))
	else
		calleeText = tok(p)
		args = table.pack(...)
	end
	local a1 = args[1]

	if CFG.falsy and R.type(name) == "string" and R.find("," .. CFG.falsy .. ",", "," .. name .. ",", 1, true) then
		emit({ text = calleeText .. "(" .. fmtArgs(R.unpack(args, 1, args.n)) .. ") --> false" })
		return false
	end

	if info.ns and DATATYPES[info.ns] then
		local dp = exprP(calleeText .. "(" .. fmtArgs(R.unpack(args, 1, args.n)) .. ")", info.ns)

		INFO[dp].ctor = { ns = info.ns, fn = name, args = args }
		return dp
	end

	if name == "Connect" or name == "Once" or name == "ConnectParallel" then
		local sig = INFO[info.parent]
		local sigName = sig and methodName(sig)
		if CFG.input_text ~= nil then

			for _, bp in R.pairs(BYID) do
				local bi = INFO[bp]
				if bi.created and bi.className == "TextBox" and bi.props.Text ~= CFG.input_text then
					bi.props.Text = CFG.input_text
					local rb = REALV[bp]
					if rb ~= nil then R.pcall(function() rb.Text = CFG.input_text end) end
				end
			end
		end
		local fnTok = R.type(a1) == "function" and captureFunction(a1, SIGNAL_PARAMS[sigName] or { "..." }, nil, "handler") or fmt(a1)
		local conn = callP(calleeText .. "(" .. fnTok .. ")", "connection", "RBXScriptConnection")
		INFO[conn].props.Connected = true
		return conn
	end
	if name == "Wait" and isMethod then

		local sp = SIGNAL_PARAMS[methodName(INFO[info.parent])]
		if sp and (sp[1] == "deltaTime" or sp[2] == "deltaTime") then
			emit({ text = calleeText .. "()" })
			onWait()
			if sp[2] == "deltaTime" then return 1, 1 / 60 end
			return 1 / 60
		end
		callP(calleeText .. "()", "result")
		local r = BYID[nextId]
		onWait()
		return r
	end

	if name == "GetService" or name == "FindService" then
		local svc = a1
		if R.type(svc) == "string" and serviceCache[svc] then
			return serviceCache[svc]
		end

		if R.type(svc) == "string" and not API.classes[svc] then
			if name == "FindService" then return nil end
			R.error(R.fmt("'%s' is not a valid Service name", svc), 0)
		end
		local r = callP(calleeText .. "(" .. fmtArgs(R.unpack(args, 1, args.n)) .. ")", R.type(svc) == "string" and svc or "service", "Instance", true)
		if R.type(svc) == "string" and API.classes[svc] then
			INFO[r].className = svc
			INFO[r].props.Name = svc
			INFO[r].props.ClassName = svc
			INFO[r].props.Parent = GAMEP
		end
		if R.type(svc) == "string" then serviceCache[svc] = r end
		return r
	end

	if name == "GetSecret" and isMethod then
		emit({ text = calleeText .. "(" .. fmtArgs(R.unpack(args, 1, args.n)) .. ") -- errors" })
		R.error("Can't find secret with given key", 0)
	end

	if (name == "SetTeleportSetting" or name == "GetTeleportSetting") and isMethod then
		local store = INFO[info.parent].tpSettings or {}
		INFO[info.parent].tpSettings = store
		if name == "SetTeleportSetting" then
			emit({ text = calleeText .. "(" .. fmtArgs(R.unpack(args, 1, args.n)) .. ")" })
			if args[1] ~= nil then store[args[1]] = args[2] end
			return
		end
		return args[1] ~= nil and store[args[1]] or nil
	end

	local self = isMethod and info.parent or nil
	local sinfo = self and INFO[self]
	if sinfo and sinfo.tname == "RBXScriptConnection" and name == "Disconnect" then
		emit({ text = calleeText .. "()" })
		sinfo.props.Connected = false
		return
	end
	if sinfo and sinfo.tname == "Enum" and sinfo.enumName then
		local e = API.enums[sinfo.enumName]
		if name == "GetEnumItems" then
			local list = {}
			for _, it in e.items do R.insert(list, enumItem(sinfo.enumName, it.Name)) end
			return list
		elseif name == "FromName" then
			return (R.type(a1) == "string" and e.byName[a1]) and enumItem(sinfo.enumName, a1) or nil
		elseif name == "FromValue" then
			local it = e.byValue[a1]
			return it and enumItem(sinfo.enumName, it.Name) or nil
		end
	end
	if sinfo and sinfo.tname == "EnumItem" and name == "IsA" then
		return a1 == sinfo.enumName
	end
	if self and RUNSERVICE_BOOL[name] ~= nil then
		return RUNSERVICE_BOOL[name]
	end
	if sinfo and (sinfo.created or sinfo.kids) then
		if name == "GetChildren" then
			emit({ text = calleeText .. "()" })
			return table.clone(kidsOf(self))
		elseif name == "GetDescendants" then
			emit({ text = calleeText .. "()" })
			return descendants(self, {})
		elseif (name == "FindFirstChild" or name == "WaitForChild") and R.type(a1) == "string" then
			local found = findKid(self, a1, name == "FindFirstChild" and args[2] == true)
			if found or sinfo.created then
				emit({ text = calleeText .. "(" .. fmtArgs(R.unpack(args, 1, args.n)) .. ")" })
				return found
			end
		elseif name == "Destroy" then
			emit({ text = calleeText .. "()" })
			destroyInst(self)
			return
		elseif name == "ClearAllChildren" then
			emit({ text = calleeText .. "()" })
			for _, c in table.clone(kidsOf(self)) do destroyInst(c) end
			return
		elseif name == "IsA" and sinfo.created then
			return a1 == sinfo.className or a1 == "Instance" or (a1 == "GuiObject" and sinfo.className == "Frame")
				or (a1 == "BasePart" and (sinfo.className == "Part" or sinfo.className == "MeshPart"))
		end
	end
	if name == "IsA" or name == "IsDescendantOf" or name == "IsAncestorOf" then
		return true
	end
	if name == "GetLogHistory" then

		return {}
	end

	if name == "HttpGet" or name == "HttpGetAsync" or name == "HttpPost" or name == "HttpPostAsync"
		or name == "GetAsync" or name == "PostAsync" or name == "RequestAsync" then
		if R.type(a1) == "string" then remember(urls, a1) end
		return callP(calleeText .. "(" .. fmtArgs(R.unpack(args, 1, args.n)) .. ")", "response", "string")
	end

	if name == "DecompressBuffer" and isMethod and __ZSTD ~= nil then
		local okb, cstr = R.pcall(buffer.tostring, a1)
		if okb and R.type(cstr) == "string" then
			local n = #cstr
			local h1, h2 = {}, {}
			for i = 1, 8 do
				if i <= n then h1[i] = R.fmt("%02x", R.byte(cstr, i)) end
			end
			for i = n - 7, n do
				if i >= 1 then h2[#h2 + 1] = R.fmt("%02x", R.byte(cstr, i)) end
			end
			local hit = __ZSTD[n .. ":" .. R.concat(h1) .. ":" .. R.concat(h2)]
			if R.type(hit) == "string" then
				emit({ text = calleeText .. "(" .. fmtArgs(R.unpack(args, 1, args.n)) .. ")" })
				return buffer.fromstring(hit)
			end
			R.print("[zstd] miss: " .. n .. " compressed bytes, no pre-decoded frame")
		end
	end

	if name == "FireServer" or name == "InvokeServer" or name == "Fire" or name == "Invoke" then
		remember(remotes, info.parent)
	end

	if not NATIVE and sinfo and sinfo.className == "Path2D" and name == "SetControlPoints" then

		sinfo.p2dSegs = nil
		sinfo.p2dPoints = R.type(a1) == "table" and not isP(a1) and table.clone(a1) or nil
		sinfo.p2dSet = true
		local W, H = CHAIN.p2d.frameSize(self)
		if CFG.p2d_debug then
			local par = sinfo.props and sinfo.props.Parent
			local sz = isP(par) and INFO[par].props and INFO[par].props.Size
			R.print("P2DDBG W,H", W, H, "a1", R.type(a1), isP(a1), "parent", isP(par), "size", isP(sz),
				isP(sz) and R.tostring(INFO[sz].ctor and INFO[sz].ctor.fn), isP(sz) and INFO[sz].text)
		end
		if W and R.type(a1) == "table" and not isP(a1) then
			local ok, segs = R.pcall(CHAIN.p2d.segments, a1, W, H)
			if CFG.p2d_debug then R.print("P2DDBG segments", ok, R.tostring(segs)) end
			if ok and segs and #segs > 0 then
				sinfo.p2dSegs, sinfo.p2dW, sinfo.p2dH = segs, W, H
			end
		end
	end

	if not NATIVE and sinfo and sinfo.className == "Path2D" and sinfo.created then
		if name == "GetMaxControlPoints" then
			emit({ text = calleeText .. "()" })
			return 100
		elseif name == "GetControlPoints" and (sinfo.p2dPoints or not sinfo.p2dSet) then
			emit({ text = calleeText .. "()" })
			return table.clone(sinfo.p2dPoints or {})
		elseif (name == "GetLength" or name == "GetBoundingRect" or (R.type(name) == "string"
			and R.find(name, "OnCurve", 1, true))) and not isP(sinfo.props.Parent) then
			emit({ text = calleeText .. "(" .. fmtArgs(R.unpack(args, 1, args.n)) .. ")" })
			R.error("Attempting to use Path2D with invalid parent", 0)
		end
	end
	if not NATIVE and sinfo and sinfo.className == "Path2D" and R.type(name) == "string" and name ~= "SetControlPoints" then
		local rec = __P2D and __P2D[p2dKey(name, args)]
		if rec and CFG.p2d_check then

			local ok, r = R.pcall(CHAIN.p2d.answer, self, name, args[1])
			R.print("\0P2DCHECK " .. p2dKey(name, args) .. "\t" .. R.tostring(rec) .. "\t" .. R.tostring(ok and r)
				.. "\t" .. ((ok and r == rec) and "same" or "DIFF"))
		end
		if not rec and not CFG.p2d_nomodel then
			local ok, r = R.pcall(CHAIN.p2d.answer, self, name, args[1])
			if ok and r then
				rec = r
				R.insert(P2D_LOG, p2dKey(name, args) .. "\t" .. r .. "\tmodel")
			end
		end
		if not rec then P2D_MISS = true end
		if rec then
			local text = calleeText .. "(" .. fmtArgs(R.unpack(args, 1, args.n)) .. ")"
			local vals = {}
			local n = 0
			for field in string.gmatch(rec, "[^\t]+") do
				n += 1
				vals[n] = p2dDecode(field, text)
			end
			if n == 1 and isP(vals[1]) then
				local cp = callP(text, R.match(name, "^Get(%u%w*)$") or "result", INFO[vals[1]].tname)
				INFO[cp].props = INFO[vals[1]].props
				return cp
			end
			emit({ text = text })
			return R.unpack(vals, 1, n)
		end
	end

	if self and REALV[self] ~= nil and R.type(name) == "string" and not NO_NATIVE_METHOD[name] then
		local r = REALV[self]
		local isInst = R.typeof(r) == "Instance"
		local u = unwrapArgs(args)
		if u then
			local res = table.pack(R.pcall(function() return r[name](r, R.unpack(u, 1, u.n)) end))
			if not res[1] then
				if not isInst and res[2] ~= CHAIN.DT_UNSUPPORTED then R.error(res[2], 0) end
			else
				local text = calleeText .. "(" .. fmtArgs(R.unpack(args, 1, args.n)) .. ")"
				local hint0 = R.match(name, "^Get(%u%w*)$") or "result"
				hint0 = R.gsub(hint0, "^%u", string.lower)
				if isInst and r.ClassName == "Path2D" then
					local enc = {}
					for i = 2, res.n do enc[#enc + 1] = p2dEncode(res[i]) or "?" end
					R.insert(P2D_LOG, p2dKey(name, args) .. "\t" .. R.concat(enc, "\t"))
				end
				local outv, good = {}, true
				for i = 2, res.n do
					local w, ok = wrapReal(res[i], text, hint0)
					if not ok then good = false break end
					outv[i - 1] = w
				end
				if good then

					if not isInst then return R.unpack(outv, 1, res.n - 1) end
					if res.n == 2 and isP(outv[1]) then

						local cp = callP(text, hint0, INFO[outv[1]].tname)
						REALV[cp] = res[2]
						return cp
					end
					emit({ text = text })
					return R.unpack(outv, 1, res.n - 1)
				end
			end
		end
	end

	local hint
	if name == "FindFirstChild" or name == "WaitForChild" or name == "FindFirstChildOfClass"
		or name == "FindFirstChildWhichIsA" or name == "FindFirstAncestor" or name == "FindFirstAncestorOfClass"
		or name == "FindFirstAncestorWhichIsA" or name == "FindFirstDescendant" then
		hint = R.type(a1) == "string" and a1 or "child"
	elseif name == "new" and info.parent and INFO[info.parent].kind == "name" and INFO[info.parent].name == "Instance" then
		hint = R.type(a1) == "string" and a1 or "instance"
	elseif name and CLASS_HINT[name] then
		hint = CLASS_HINT[name]
	elseif name == "Clone" then
		hint = "clone"
	elseif name == "Create" and isMethod and INFO[info.parent].className == "TweenService" then
		hint = "tween"
	elseif name then
		hint = R.match(name, "^Get(%u%w*)$") or R.match(name, "^Find(%u%w*)$")
		local made = R.match(name, "^Create(%u%w*)$") or R.match(name, "^New(%u%w*)$")
			or R.match(name, "^Add(%u%w*)$") or R.match(name, "^Make(%u%w*)$")
		if hint then
			hint = R.gsub(hint, "^%u", string.lower)
		else
			hint = made or "result"
		end
	else
		hint = "result"
	end
	return callP(calleeText .. "(" .. fmtArgs(R.unpack(args, 1, args.n)) .. ")", hint)
end

local OPAQUE = { EnumItem = 1, Enum = 1, Enums = 1, RBXScriptSignal = 1, RBXScriptConnection = 1 }
local function opaqueType(v)
	if not isP(v) then return nil end
	local info = INFO[v]
	if OPAQUE[info.tname] then return info.tname end
	if info.created or (info.className and info.kind ~= "call" or info.kind == "name" and info.className) then
		return "Instance"
	end
	return nil
end
local function luaTypeName(v)
	return opaqueType(v) or R.typeof(v)
end
local function arithError(opname, a, b)
	if opaqueType(a) or opaqueType(b) then
		R.error(R.fmt("attempt to perform arithmetic (%s) on %s and %s", opname, luaTypeName(a), luaTypeName(b)), 3)
	end
end
local ARITH = {
	["+"] = function(a, b) return a + b end, ["-"] = function(a, b) return a - b end,
	["*"] = function(a, b) return a * b end, ["/"] = function(a, b) return a / b end,
	["//"] = function(a, b) return a // b end, ["%"] = function(a, b) return a % b end,
	["^"] = function(a, b) return a ^ b end,
}
local OPNAMES = { ["+"] = "add", ["-"] = "sub", ["*"] = "mul", ["/"] = "div", ["//"] = "idiv", ["%"] = "mod", ["^"] = "pow" }
local function binop(op, tname)
	return function(a, b)
		arithError(OPNAMES[op], a, b)
		local ra, oka = realOf(a)
		local rb, okb = realOf(b)
		if oka and okb then

			local ok, r = R.pcall(ARITH[op], ra, rb)
			if not ok and NATIVE then R.error(r, 2) end
			if ok then
				local w, good = wrapReal(r, "(" .. fmt(a) .. " " .. op .. " " .. fmt(b) .. ")", nil)
				if good then return w end
			end
		end
		return exprP("(" .. fmt(a) .. " " .. op .. " " .. fmt(b) .. ")", tname or (isP(a) and INFO[a].tname) or (isP(b) and INFO[b].tname) or "number")
	end
end

local METHOD_PREFIX = { "Get", "Find", "Wait", "Is", "Clone", "Destroy", "Connect", "Once", "Fire", "Invoke",
	"Set", "Clear", "Remove", "Add", "Load", "Play", "Stop", "Pause", "Resume", "Adjust", "Move", "Pivot",
	"Apply", "Take", "Kick", "Teleport", "Emit", "Create", "Raycast", "Blockcast", "Spherecast", "Shapecast",
	"Http", "Request", "JSON", "Generate", "Compute", "Change", "Equip", "Unequip", "Preload", "Bind", "Unbind",
	"Disconnect", "Activate", "Deactivate", "Update", "Serialize", "Break", "Reset", "Scale", "To", "Lerp",
	"Navigate", "Render", "Open", "Close", "Enable", "Disable", "Insert", "Show", "Hide", "Tween", "Capture",
	"Post", "Publish", "Subscribe", "Increment", "Decrement", "Save", "Read", "Write", "Check", "Can", "Has",
	"Prompt", "Send", "Kill", "Spawn", "Transform", "Invert", "Reverse", "Clamp", "Sample", "Evaluate",
	"Batch", "Sync", "Query", "Register", "Unregister", "Rebuild", "Refresh", "Cancel", "Dump", "Test", "From" }
local METHOD_EXACT = { connect = 1, wait = 1, disconnect = 1, Wait = 1, Connect = 1, Once = 1, ConnectParallel = 1,
	Disconnect = 1, Destroy = 1, Clone = 1, Remove = 1, ClearAllChildren = 1, Kick = 1, Play = 1, Stop = 1,
	findFirstChild = 1, children = 1, getChildren = 1, clone = 1, destroy = 1, remove = 1, isA = 1 }
local methodCache = R.setmetatable({}, { __mode = "k" })
local METHODP = R.setmetatable({}, { __mode = "k" })
METHODP_REF = METHODP
function isMethodName(k)
	if R.type(k) ~= "string" then return false end
	if METHOD_EXACT[k] then return true end
	for _, pre in METHOD_PREFIX do
		if R.sub(k, 1, #pre) == pre and R.match(R.sub(k, #pre + 1, #pre + 1), "^%u$") then
			return true
		end
	end
	return false
end

local SHARED_METHODS = {}
local SIGNAL_T = { RBXScriptSignal = true, RBXScriptConnection = true }
function methodFn(p, k)
	local want = INFO[p].tname
	if SIGNAL_T[want] then

		local ip = indexP(p, k)
		local f = function(...)
			local self = ...
			if R.select("#", ...) == 0 then
				R.error(R.fmt("missing argument #1 to '%s' (%s expected)", k, want), 0)
			end
			if not (isP(self) and INFO[self].tname == want) then
				R.error(R.fmt("invalid argument #1 to '%s' (%s expected, got %s)", k, want, luaTypeName(self)), 0)
			end
			return PMT.__call(indexP(self, k), ...)
		end
		CFUNCS[f] = true
		CNAME[f] = k
		METHODP[f] = ip
		return f
	end
	local ck = R.tostring(INFO[p].tname) .. "|" .. R.tostring(k)
	local f = SHARED_METHODS[ck]
	if f then return f end
	local ip = indexP(p, k)
	f = function(...)
		local self = ...
		if not isP(self) then
			R.error("Expected ':' not '.' calling member function " .. k, 0)
		end
		return PMT.__call(indexP(self, k), ...)
	end
	CFUNCS[f] = true
	CNAME[f] = k
	METHODP[f] = ip
	SHARED_METHODS[ck] = f
	return f
end

local SIGNAL_MEMBERS = {
	RBXScriptSignal = { Connect = "method", ConnectParallel = "method", Once = "method", Wait = "method" },
	RBXScriptConnection = { Connected = "prop", Disconnect = "method" },
}
PMT.__index = function(p, k)
	local info = INFO[p]
	if CFG.trace or CFG.ptrace then R.print("[index]", info.name or info.hint, k) end
	if k == "Parent" and (info.nilParent or info.created) then return info.props.Parent end

	if k == "Parent" and info.props.Parent == nil and info.tname == "Instance" and p ~= WORKSPACEP then
		local depth, q = 0, p
		while q and INFO[q] and INFO[q].key == "Parent" do
			depth += 1
			q = INFO[q].parent
		end
		if depth >= 3 then return WORKSPACEP end
	end
	if SIGNAL_MEMBERS[info.tname] then
		local m = SIGNAL_MEMBERS[info.tname][k]
		if m == "method" then return methodFn(p, k) end
		if m == nil then
			R.error(R.fmt("%s is not a valid member of %s", R.tostring(k), info.tname), 0)
		end
	end
	if (k == "AbsolutePosition" or k == "AbsoluteSize") and (CHAIN.isGuiObject(p) or (info.className == "ScreenGui")) then
		local x, y
		if k == "AbsolutePosition" then
			x, y = CHAIN.computeAbsolutePosition(p)
		else
			x, y = CHAIN.computeAbsoluteSize(p)
		end
		local v2
		if NATIVE then
			v2 = Vector2.new(x, y)
		else
			local v2Lib = __ROBLOX and __ROBLOX.datatypes and __ROBLOX.datatypes.Vector2
			v2 = v2Lib and v2Lib.new(x, y)
		end
		if v2 then
			local res, ok = wrapReal(v2, tok(p) .. "." .. k, k)
			if ok then return res end
		end
	end
	local v = info.props[k]
	if v ~= nil then return v end
	local rv = REALV[p]
	if rv ~= nil and R.type(k) == "string" then
		local isInst = R.typeof(rv) == "Instance"
		local ok, x = R.pcall(function() return rv[k] end)
		if not ok then
			if not isInst and x ~= CHAIN.DT_UNSUPPORTED then R.error(x, 2) end
		elseif R.type(x) ~= "function" then
			local w, good = wrapReal(x, tok(p) .. keySuffix(k), k)
			if good then return w end
		end
	end
	if info.genv then
		return nil
	end
	if info.tname == "Enums" and R.type(k) == "string" and API.enums[k] then
		return enumType(k)
	end
	if info.tname == "Enum" and info.enumName then
		local e = API.enums[info.enumName]
		if e and e.byName[k] then return enumItem(info.enumName, k) end
		if k == "GetEnumItems" or k == "FromName" or k == "FromValue" then return methodFn(p, k) end
	end
	if info.tname == "EnumItem" and k == "IsA" then
		return methodFn(p, k)
	end

	if (info.tname == "Faces" or info.tname == "Axes") and info.ctor and R.type(k) == "string" then
		local axisOf = { Right = "X", Left = "X", Top = "Y", Bottom = "Y", Back = "Z", Front = "Z" }
		local isFaces = info.tname == "Faces"
		local want = isFaces and (axisOf[k] and k) or (axisOf[k] or ((k == "X" or k == "Y" or k == "Z") and k))
		if want then
			local a = info.ctor.args
			for i = 1, a.n do
				local ai = isP(a[i]) and INFO[a[i]]
				if ai and ai.tname == "EnumItem" then
					local n = ai.props.Name
					if isFaces then
						if ai.enumName == "NormalId" and n == want then return true end
					elseif (ai.enumName == "NormalId" and axisOf[n] == want) or (ai.enumName == "Axis" and n == want) then
						return true
					end
				end
			end
			return false
		end
	end
	local dm = DT_MEMBERS[info.tname]
	if dm and R.type(k) == "string" and dm[k] and REALV[p] == nil then
		if dm[k] == "n" then return 0 end
		local c = indexP(p, k)
		INFO[c].tname = dm[k]
		INFO[c].className = nil
		return c
	end
	local cls = info.className
	if cls and API.classes[cls] and R.type(k) == "string" then
		local kind = memberKind(cls, k)
		if kind == "method" then return methodFn(p, k) end
		if kind == "event" then

			local c = newP({ kind = "index", parent = p, key = k, tname = "RBXScriptSignal", hint = k,
				sigKey = info.id .. "." .. k })
			return c
		end
		if kind == "prop" then
			local vt = propType(cls, k)
			if vt and NUMERIC_T[vt] then return NUM_DEFAULT[k] or 0 end
			local c = indexP(p, k)
			if vt and DT_MEMBERS[vt] then
				INFO[c].tname = vt
				INFO[c].className = nil
			elseif vt == "bool" then
				INFO[c].tname = "boolean"
				INFO[c].className = nil
			elseif vt == "string" then
				INFO[c].tname = "string"
				INFO[c].className = nil
			end
			return c
		end
	end
	if isMethodName(k) and info.tname ~= "table" then
		return methodFn(p, k)
	end
	return indexP(p, k)
end
PMT.__newindex = function(p, k, v)
	local info = INFO[p]
	if CFG.ptrace then R.print("[newindex]", info.name or info.hint, k, R.typeof(v)) end
	if k == "Parent" and info.destroyed then
		R.error(R.fmt("The Parent property of %s is locked, current parent: NULL, new parent %s",
			instName(p), isP(v) and instName(v) or "NULL"), 0)
	end
	emit({ text = tok(p) .. keySuffix(k) .. " = " .. fmt(v) })
	local rv = REALV[p]

	if NATIVE and rv ~= nil and k ~= "Parent" and R.type(k) == "string" then
		local u = unwrapArgs(table.pack(v))
		if u then
			local ok, err = R.pcall(function() rv[k] = u[1] end)
			if not ok then R.error(err, 2) end
		end
	end
	if k == "Parent" and (v == nil or isP(v)) then
		setParent(p, v)
	else
		info.props[k] = v
	end
end
PMT.__call = onCall
PMT.__tostring = function(p)
	if REALV[p] ~= nil then return R.tostring(REALV[p]) end
	return "<" .. (INFO[p].hint or "proxy") .. ">"
end
PMT.__concat = function(a, b)
	if opaqueType(a) or opaqueType(b) then
		R.error(R.fmt("attempt to concatenate %s with %s", luaTypeName(a), luaTypeName(b)), 2)
	end
	return exprP(fmt(a) .. " .. " .. fmt(b), "string")
end
PMT.__add = binop("+")
PMT.__sub = binop("-")
PMT.__mul = binop("*")
PMT.__div = binop("/")
PMT.__idiv = binop("//")
PMT.__mod = binop("%")
PMT.__pow = binop("^")
PMT.__unm = function(a)
	if opaqueType(a) then
		R.error(R.fmt("attempt to perform arithmetic (unm) on %s", luaTypeName(a)), 2)
	end
	if REALV[a] ~= nil then
		local ok, r = R.pcall(function() return -REALV[a] end)
		if not ok and NATIVE then R.error(r, 2) end
		if ok then
			local w, good = wrapReal(r, "(-" .. fmt(a) .. ")", nil)
			if good then return w end
		end
	end
	return exprP("(-" .. fmt(a) .. ")", INFO[a].tname)
end
PMT.__len = function(p)
	return 1
end
PMT.__eq = function(a, b)
	if CFG.ptrace then R.print("[eq]", INFO[a] and (INFO[a].name or INFO[a].hint), INFO[b] and (INFO[b].name or INFO[b].hint)) end
	local ra, rb = REALV[a], REALV[b]
	if ra ~= nil and rb ~= nil then return ra == rb end
	local ia, ib = INFO[a], INFO[b]
	if ia and ib and ia.sigKey and ia.sigKey == ib.sigKey then return true end
	return R.rawequal(a, b)
end
PMT.__lt = function(a, b)
	comment("condition: " .. fmt(a) .. " < " .. fmt(b) .. "  (assumed true)")
	return true
end
PMT.__le = function(a, b)
	comment("condition: " .. fmt(a) .. " <= " .. fmt(b) .. "  (assumed false)")
	return false
end
PMT.__iter = function(p)
	return iterProxy(p, nil)
end
PMT.__metatable = "The metatable is locked"

local function anyProxy(...)
	for i = 1, R.select("#", ...) do
		if isP((R.select(i, ...))) then return true end
	end
	return false
end

local function wrapLib(libName, lib, tname)
	local out = {}
	for k, f in R.pairs(lib) do
		if R.type(f) == "function" then
			local label = libName .. "." .. k
			out[k] = function(...)
				if anyProxy(...) then
					return exprP(label .. "(" .. fmtArgs(...) .. ")", tname)
				end
				return f(...)
			end
		else
			out[k] = f
		end
	end
	return out
end

function genvTable(label)
	local t = {}
	GENVNAME[t] = label
	local shadow = {}
	CHAIN.genvShadow = CHAIN.genvShadow or {}
	CHAIN.genvShadow[t] = shadow
	return R.setmetatable(t, {
		__newindex = function(self, k, v)
			emit({ text = label .. keySuffix(k) .. " = " .. fmt(v) })
			R.rawset(self, k, v)
			shadow[k] = v
		end,
	})
end

CHAIN.syncGenv = function()
	CHAIN.syncing = true
	for t, shadow in R.next, CHAIN.genvShadow do
		local label = GENVNAME[t]
		for k, v in R.next, t do
			if not R.rawequal(shadow[k], v) then
				shadow[k] = v
				emit({ text = label .. keySuffix(k) .. " = " .. fmt(v) })
			end
		end
		for k in R.next, shadow do
			if R.rawget(t, k) == nil then
				shadow[k] = nil
				emit({ text = label .. keySuffix(k) .. " = nil" })
			end
		end
	end
	CHAIN.syncing = false
end

ENV = {}
local E = ENV
local RandomMT = {}
local RANDOM_STATE
local GENV = genvTable("getgenv()")
local collected = {}

E.string = wrapLib("string", string, "string")
E.math = wrapLib("math", math, "number")
E.table = table
E.bit32 = bit32
E.coroutine = coroutine

local UNorm = (function()
	local U = __UNICODE or { decomp = "", ccc = "", comp = "" }
	local decomp, ccc, comp = {}, {}, {}
	for k, v in string.gmatch(U.decomp, "(%x+):([%x,]+)") do
		local list = {}
		for x in string.gmatch(v, "%x+") do R.insert(list, R.tonumber(x, 16)) end
		decomp[R.tonumber(k, 16)] = list
	end
	for k, v in string.gmatch(U.ccc, "(%x+):(%x+)") do
		ccc[R.tonumber(k, 16)] = R.tonumber(v, 16)
	end
	for a, b, c in string.gmatch(U.comp, "(%x+),(%x+):(%x+)") do
		comp[R.tonumber(a, 16) * 0x110000 + R.tonumber(b, 16)] = R.tonumber(c, 16)
	end
	local SBase, LBase, VBase, TBase = 0xAC00, 0x1100, 0x1161, 0x11A7
	local LCount, VCount, TCount = 19, 21, 28
	local NCount = VCount * TCount
	local SCount = LCount * NCount

	local function decompose(s)
		local out = {}
		for _, cp in utf8.codes(s) do
			local si = cp - SBase
			if si >= 0 and si < SCount then
				R.insert(out, LBase + si // NCount)
				R.insert(out, VBase + (si % NCount) // TCount)
				local t = si % TCount
				if t ~= 0 then R.insert(out, TBase + t) end
			elseif decomp[cp] then
				for _, x in decomp[cp] do R.insert(out, x) end
			else
				R.insert(out, cp)
			end
		end

		local i = 1
		while i <= #out do
			if (ccc[out[i]] or 0) > 0 then
				local j = i
				while j + 1 <= #out and (ccc[out[j + 1]] or 0) > 0 do j += 1 end
				for a = i + 1, j do
					local x = out[a]
					local cx = ccc[x]
					local b = a - 1
					while b >= i and ccc[out[b]] > cx do
						out[b + 1] = out[b]
						b -= 1
					end
					out[b + 1] = x
				end
				i = j + 1
			else
				i += 1
			end
		end
		return out
	end

	local function compose(cps)
		local out = {}
		local starter = nil
		local lastClass = -1
		for _, cp in cps do
			local c = ccc[cp] or 0
			local done = false
			if starter then
				local s = out[starter]

				local li, vi = s - LBase, cp - VBase
				if li >= 0 and li < LCount and vi >= 0 and vi < VCount and starter == #out then
					out[starter] = SBase + (li * VCount + vi) * TCount
					done = true
				else
					local si, ti = s - SBase, cp - TBase
					if si >= 0 and si < SCount and si % TCount == 0 and ti > 0 and ti < TCount and starter == #out then
						out[starter] = s + ti
						done = true
					end
				end
				if not done and (lastClass < c or (lastClass == 0 and starter == #out)) then
					local p = comp[s * 0x110000 + cp]
					if p and (starter == #out or lastClass < c) then
						out[starter] = p
						done = true
					end
				end
			end
			if not done then
				R.insert(out, cp)
				if c == 0 then
					starter = #out
					lastClass = 0
				else
					lastClass = c
				end
			end
		end
		return out
	end

	local function pack(cps)
		local parts = {}
		for i, cp in cps do parts[i] = utf8.char(cp) end
		return R.concat(parts)
	end
	return {
		nfd = function(s) return pack(decompose(s)) end,
		nfc = function(s) return pack(compose(decompose(s))) end,
	}
end)()

E.utf8 = (function()
	local t = {}
	for k, v in R.pairs(utf8) do t[k] = v end
	t.graphemes = function(s, i, j)
		local list = {}
		for p, c in utf8.codes(s) do R.insert(list, { p, p + #utf8.char(c) - 1 }) end
		local n = 0
		return function()
			n += 1
			local g = list[n]
			if g then return g[1], g[2] end
		end
	end
	t.nfcnormalize = function(s) return UNorm.nfc(s) end
	t.nfdnormalize = function(s) return UNorm.nfd(s) end
	return t
end)()
E.vector = vector
E.os = { clock = os.clock, time = os.time, date = os.date, difftime = os.difftime }
E.debug = debug
E.buffer = (function()
	local b = {}

	local ROBLOX_BUFFER = {}
	for n in string.gmatch("copy,create,fill,fromstring,len,readbits,readf32,readf64,readi16,readi32,readi8,"
		.. "readstring,readu16,readu32,readu8,tostring,writebits,writef32,writef64,writei16,writei32,writei8,"
		.. "writestring,writeu16,writeu32,writeu8", "[^,]+") do ROBLOX_BUFFER[n] = true end
	for k, f in R.pairs(buffer) do
		if ROBLOX_BUFFER[k] then b[k] = f end
	end

	local lastOff = -1
	local undo = {}
	for _, nm in { "writei32", "writeu32" } do
		local orig = buffer[nm]
		b[nm] = function(buf, off, v)
			if tamperCount > 0 and v >= 0 and v < 256 and off ~= lastOff + 4 and buffer.len(buf) > 4096 then

				R.error(TAMPER, 0)
			end
			if v >= 0 and v < 256 and off ~= lastOff + 4 and buffer.len(buf) > 4096 and off + 4 <= buffer.len(buf) then
				R.insert(undo, { buf, off, buffer.readu32(buf, off) })
				if #undo >= (CFG.tamper_limit or 64) then
					for i = #undo, 1, -1 do
						local u = undo[i]
						buffer.writeu32(u[1], u[2], u[3])
					end
					table.clear(undo)
					tamperCount += 1
					if not TRIGGER then noteTrigger() end
					if (CFG.oplog or CFG.inline_probe) and E.__OPDUMP then E.__OPDUMP() end
					R.error(TAMPER, 0)
				end
			elseif #undo > 0 and off == lastOff + 4 then
				table.clear(undo)
			end
			lastOff = off
			return orig(buf, off, v)
		end
	end
	if not CFG.dump_strings then return b end
	b.readstring = function(buf, off, len)
		local s = buffer.readstring(buf, off, len)
		R.insert(collected, s)
		return s
	end
	b.tostring = function(buf)
		local s = buffer.tostring(buf)
		R.insert(collected, s)
		return s
	end
	return b
end)()

for _, k in { "assert", "error", "next", "rawget", "rawset", "rawequal", "rawlen", "select", "setmetatable",
	"getmetatable", "unpack", "newproxy", "gcinfo", "_VERSION" } do
	E[k] = REAL_G[k]
end

E.type = function(...)
	local v = ...
	if isP(v) then
		local t = INFO[v].tname
		if t == "string" or t == "number" or t == "table" or t == "boolean" then return t end
		return "userdata"
	end
	return R.type(...)
end
E.typeof = function(...)
	local v = ...
	if CFG.ptrace then R.print("[typeof]", isP(v) and (INFO[v].name or INFO[v].hint) or R.typeof(v)) end
	if isP(v) then
		local t = INFO[v].tname
		if t == "table" then return "table" end
		return t or "Instance"
	end
	if RANDOM_STATE and RANDOM_STATE[v] then return "Random" end
	local t = R.typeof(...)
	if t == "vector" then return "Vector3" end
	return t
end
E.tostring = function(...)
	local v = ...
	if CFG.ptrace then R.print("[tostring]", isP(v) and (INFO[v].name or INFO[v].hint) or R.typeof(v)) end
	if isP(v) then
		local info = INFO[v]
		if info.tname == "EnumItem" then return "Enum." .. info.enumName .. "." .. info.props.Name end
		if info.tname == "Enum" then return info.enumName end
		if info.tname == "Enums" then return "Enums" end
		if REALV[v] ~= nil then return R.tostring(REALV[v]) end

		if R.type(info.props.Name) == "string" and (info.className or opaqueType(v) == "Instance") then return info.props.Name end
		return exprP("tostring(" .. tok(v) .. ")", "string")
	end
	return R.tostring(...)
end
E.tonumber = function(...)
	local v = ...
	if isP(v) then return exprP("tonumber(" .. tok(v) .. ")", "number") end
	return R.tonumber(...)
end

E.next = function(...)
	local t = ...
	if isP(t) then
		if R.select("#", ...) < 1 then R.error("missing argument #1 to 'next' (table expected)", 0) end
		return nil
	end
	return R.next(...)
end
E.pairs = function(...)
	local t = ...
	if isP(t) then return iterProxy(t, "pairs"), t, nil end
	local f, s0, c0 = R.pairs(...)
	if f == R.next then f = E.next end
	return f, s0, c0
end
E.ipairs = function(...)
	local t = ...
	if isP(t) then return iterProxy(t, "ipairs"), t, 0 end
	return R.ipairs(...)
end

E.pcall = R.pcall
E.ypcall = R.pcall
E.xpcall = R.xpcall

E.getfenv = R.getfenv
E.setfenv = function(x, env)
	if R.type(x) == "number" then
		return R.setfenv(x == 0 and 0 or x + 1, env)
	end

	if CFUNCS[x] or isP(x) or (R.type(x) == "function" and debug.info(x, "s") == HARNESS_SRC0) then
		R.error("'setfenv' cannot change environment of given object", 0)
	end
	return R.setfenv(x, env)
end
E.print = function(...)
	emit({ text = "print(" .. fmtArgs(...) .. ")" })
end
E.warn = function(...)
	emit({ text = "warn(" .. fmtArgs(...) .. ")" })
end

local NEWCHUNKS = {}
local function srcKey(src)
	local h = 0
	for i = 1, #src, 4096 do
		local bytes = { R.byte(src, i, math.min(i + 4095, #src)) }
		for _, b in bytes do h = (h * 31 + b) % 2147483648 end
	end
	return #src .. "_" .. h
end
E.loadstring = function(src, chunkname)
	if isP(src) then
		return exprP("loadstring(" .. tok(src) .. ")", "function")
	end
	local patched = nil
	if R.type(src) == "string" and #src >= 4096 then
		local key = srcKey(src)
		patched = __CHUNKS and __CHUNKS[key]
		if not patched and not NEWCHUNKS[key] then
			NEWCHUNKS[key] = src
			R.insert(NEWCHUNKS, key)

			R.print("\0CHUNK " .. key)
			R.print((R.gsub(src, ".", function(c)
				return R.fmt("%02x", R.byte(c))
			end)))
		end

		if CFG.spin and not (patched and R.find(patched, "__SPIN.n", 1, true)) then
			patched = R.gsub(patched or src, "while true do [%w_, ]-=[%a_][%w_]*%[[%a_][%w_]*%];",
				"%0__SPIN.n=__SPIN.n+1;if __SPIN.n>=__SPIN.step then __SPIN.f()end;")
		end
	end
	local f, err = R.loadstring(patched or src, chunkname)
	if not f then return nil, err end
	R.setfenv(f, ENV)
	comment("loadstring() of " .. #src .. " bytes: " .. quote(R.sub(src, 1, 200)))
	return f
end
E.require = function(m)
	return callP("require(" .. fmt(m) .. ")", "module")
end

local function spawnLike(label, fn, ...)
	if R.type(fn) == "function" then
		local args = table.pack(...)
		lastThread = nil
		local okc, tokf = R.pcall(captureFunction, fn, nil, args)
		if not okc then

			local fid = FUNCS[fn]
			if fid then
				local p = newP({ kind = "call", tname = "thread", hint = "thread" })
				local st = { call = label .. "(" .. fid .. ")", res = p }
				INFO[p].stmt = st
				R.insert(curBlock().lines, st)
			end
			R.error(tokf, 0)
		end
		local th = lastThread
		local p = callP(label .. "(" .. tokf .. (args.n > 0 and (", " .. fmtArgs(...)) or "") .. ")", "thread", "thread")
		if th then
			THREADP[th] = p
			return th
		end
		return p
	end
	return callP(label .. "(" .. fmtArgs(fn, ...) .. ")", "thread", "thread")
end
local function doWait(label, t)
	emit({ text = label .. "(" .. (t ~= nil and fmt(t) or "") .. ")" })
	onWait()
	return (R.type(t) == "number" and t) or 0.03, R.clock()
end

local function typeName(n, ...)
	if R.select("#", ...) < n then return "no value" end
	return R.typeof((R.select(n, ...)))
end
local function argError(n, fname, expected, ...)
	R.error(R.fmt("invalid argument #%d to '%s' (%s expected, got %s)", n, fname, expected, typeName(n, ...)), 0)
end
local function checkRoutine(n, fname, ...)
	local v = R.select(n, ...)
	local t = R.type(v)
	if R.select("#", ...) < n or (t ~= "function" and t ~= "thread") then
		argError(n, fname, "function or thread", ...)
	end
	return v
end
local function checkNumber(n, fname, ...)
	local v = R.select(n, ...)
	if R.select("#", ...) >= n and v ~= nil and R.type(v) ~= "number" then
		if R.tonumber(v) then return R.tonumber(v) end
		argError(n, fname, "number", ...)
	end
	return v
end

local function scheduleLater(label, delayArg, due, fn, ...)
	if R.type(fn) == "thread" then

		local th = fn
		local args = table.pack(...)
		R.insert(DEFERRED, { rec = { params = {}, block = { lines = {}, waits = {} } }, thread = th,
			args = args, n = args.n, due = due })
		emit({ text = label .. "(" .. (delayArg and (fmt(delayArg) .. ", ") or "") .. fmt(th) .. ")" })
		return th
	end
	local args = table.pack(...)
	lastThread = nil
	local tokf = captureFunction(fn, nil, args, due)
	local th = lastThread
	local p = callP(label .. "(" .. (delayArg ~= nil and (fmt(delayArg) .. ", ") or "") .. tokf
		.. (args.n > 0 and (", " .. fmtArgs(...)) or "") .. ")", "thread", "thread")
	if th then THREADP[th] = p; return th end
	return p
end

E.task = {
	spawn = function(...)
		local fn = checkRoutine(1, "spawn", ...)
		if R.type(fn) == "thread" then
			emit({ text = "task.spawn(" .. fmt(fn) .. ")" })
			coroutine.resume(fn, R.select(2, ...))
			return fn
		end
		return spawnLike("task.spawn", ...)
	end,
	defer = function(...)
		checkRoutine(1, "defer", ...)
		return scheduleLater("task.defer", nil, 0.5, ...)
	end,
	delay = function(...)
		local t = checkNumber(1, "delay", ...)
		checkRoutine(2, "delay", ...)
		return scheduleLater("task.delay", t or 0, 1 + (t or 0), R.select(2, ...))
	end,
	wait = function(...)
		local t = checkNumber(1, "wait", ...)
		return doWait("task.wait", t)
	end,
	cancel = function(...)
		local th = R.select(1, ...)
		if R.select("#", ...) < 1 or R.type(th) ~= "thread" then
			argError(1, "cancel", "thread", ...)
		end
		emit({ text = "task.cancel(" .. fmt(th) .. ")" })
		if coroutine.status(th) == "suspended" then coroutine.close(th) end
	end,
	synchronize = function() end,
	desynchronize = function() end,
}
E.wait = function(t) return doWait("wait", t) end
E.spawn = function(fn) return spawnLike("spawn", fn) end
E.delay = function(t, fn)
	return E.task.delay(t, fn)
end
E.tick = function() return os.clock() + 1.7e9 end
E.time = os.clock
E.elapsedTime = os.clock
E.getgenv = function() return GENV end

do
	local renv
	E.getrenv = function()
		if renv then return renv end
		renv = {}
		for n in string.gmatch("assert,error,getmetatable,setmetatable,ipairs,pairs,next,pcall,xpcall,print,"
			.. "select,tonumber,tostring,type,typeof,unpack,rawequal,rawget,rawset,rawlen,gcinfo,newproxy,"
			.. "collectgarbage,getfenv,setfenv,require,_G,_VERSION,string,math,table,os,debug,bit32,coroutine,"
			.. "utf8,buffer,vector,game,Game,workspace,Workspace,script,plugin,shared,settings,UserSettings,"
			.. "tick,time,wait,delay,spawn,elapsedTime,ElapsedTime,warn,task,Enum,Instance,stats,Stats,version,"
			.. "Random,Vector3", "[^,]+") do
			renv[n] = R.rawget(E, n)
		end
		for n in DATATYPES do renv[n] = R.rawget(E, n) end
		return renv
	end
end
E._G = genvTable("_G")
E.shared = genvTable("shared")
E.game = globalP("game")
INFO[E.game].className = "DataModel"
E.Game = E.game
E.workspace = globalP("workspace")
INFO[E.workspace].className = "Workspace"
E.Workspace = E.workspace

INFO[E.game].nilParent = true
INFO[E.game].props.Name = CFG.place_name or "Game"
INFO[E.game].props.ClassName = "DataModel"
INFO[E.workspace].props.Name = "Workspace"
INFO[E.workspace].props.ClassName = "Workspace"
INFO[E.workspace].props.Parent = E.game
serviceCache.Workspace = E.workspace
GAMEP = E.game
WORKSPACEP = E.workspace
E.script = globalP("script")
INFO[E.script].className = "LocalScript"
E.plugin = nil

local NS_CONSTANTS = { zero = 1, one = 1, xAxis = 1, yAxis = 1, zAxis = 1, identity = 1 }
local NS_MEMBERS = {
	Vector3 = { "new", "zero", "one", "xAxis", "yAxis", "zAxis", "FromNormalId", "FromAxis", "fromNormalId", "fromAxis" },
	Vector2 = { "new", "zero", "one", "xAxis", "yAxis" },
	CFrame = { "new", "fromEulerAnglesXYZ", "fromEulerAnglesYXZ", "Angles", "fromOrientation", "fromAxisAngle",
		"fromMatrix", "lookAt", "lookAlong", "identity", "fromEulerAngles" },
	Color3 = { "new", "fromRGB", "fromHSV", "fromHex", "toHSV" },
	UDim2 = { "new", "fromScale", "fromOffset" },
	Font = { "new", "fromEnum", "fromName", "fromId" },
	DateTime = { "now", "fromUnixTimestamp", "fromUnixTimestampMillis", "fromUniversalTime", "fromLocalTime", "fromIsoDate" },
	BrickColor = { "new", "random", "palette", "White", "Gray", "DarkGray", "Black", "Red", "Yellow", "Green", "Blue" },
	SharedTable = { "new", "clone", "cloneAndFreeze", "increment", "isFrozen", "size", "update" },
}
local function nativeFn(label, f)
	f = tramp(f)
	CFUNCS[f] = true
	CNAME[f] = R.match(label, "([%w_]+)$")
	FNAME[f] = label
	return f
end
local function namespace(name, fields)
	local t = fields or {}
	for k, v in R.pairs(t) do
		if R.type(v) == "function" then nativeFn(name .. "." .. k, v) end
	end
	local function member(k)
		if NS_CONSTANTS[k] or R.match(k, "^%u") and name == "BrickColor" and k ~= "new" then
			local p = exprP(name .. "." .. k .. (NS_CONSTANTS[k] and "" or "()"), name)
			attachReal(p, name, k, not NS_CONSTANTS[k])
			return p
		end
		return nativeFn(name .. "." .. k, function(...)
			local p = exprP(name .. "." .. k .. "(" .. fmtArgs(...) .. ")", name)
			if CFG.ptrace then R.print("[ctor]", INFO[p].text) end
			INFO[p].ctor = { ns = name, fn = k, args = table.pack(...) }
			attachReal(p, name, k, true, ...)
			return p
		end)
	end
	for _, k in NS_MEMBERS[name] or { "new" } do
		if R.rawget(t, k) == nil then t[k] = member(k) end
	end
	return table.freeze(t)
end

local REQUIRED_ARG = {
	Path2DControlPoint = "UDim2", NumberSequenceKeypoint = "number", ColorSequenceKeypoint = "number",
	NumberSequence = "number", ColorSequence = "Color3", Ray = "Vector3", Region3 = "Vector3",
	PathWaypoint = "Vector3", Font = "string",
}
for name in DATATYPES do
	if name ~= "Vector3" then
		local fields = nil
		if REQUIRED_ARG[name] then
			local want = REQUIRED_ARG[name]
			fields = {
				new = function(...)
					if R.select("#", ...) < 1 or (...) == nil then
						R.error(R.fmt("invalid argument #1 to 'new' (%s expected, got %s)", want,
							R.select("#", ...) < 1 and "no value" or "nil"), 0)
					end
					local p = exprP(name .. ".new(" .. fmtArgs(...) .. ")", name)
					if CFG.ptrace then R.print("[ctor]", INFO[p].text) end
					INFO[p].ctor = { ns = name, fn = "new", args = table.pack(...) }
					attachReal(p, name, "new", true, ...)
					return p
				end,
			}
		end
		E[name] = namespace(name, fields)
	end
end

local function vec(x, y, z)
	return vector.create(R.tonumber(x) or 0, R.tonumber(y) or 0, R.tonumber(z) or 0)
end
E.Vector3 = namespace("Vector3", {
	new = function(x, y, z)
		if isP(x) or isP(y) or isP(z) then
			return exprP("Vector3.new(" .. fmtArgs(x, y, z) .. ")", "Vector3")
		end
		return vec(x, y, z)
	end,
	zero = vector.zero or vec(0, 0, 0),
	one = vector.one or vec(1, 1, 1),
	xAxis = vec(1, 0, 0),
	yAxis = vec(0, 1, 0),
	zAxis = vec(0, 0, 1),
})
E.Instance = namespace("Instance", {
	new = function(...)
		local className, parent = ...
		if R.type(className) ~= "string" then
			R.error(R.fmt("invalid argument #1 to 'new' (string expected, got %s)",
				R.select("#", ...) < 1 and "no value" or R.typeof(className)), 0)
		end
		local p
		if R.select("#", ...) >= 2 then
			p = callP("Instance.new(" .. fmtArgs(className, parent) .. ")", className)
		else
			p = callP("Instance.new(" .. fmt(className) .. ")", className)
		end
		local info = INFO[p]
		info.created = true
		info.className = className
		info.kids = {}
		info.props.Name = className
		info.props.ClassName = className
		if NATIVE then
			local ok, inst = R.pcall(REAL_G.Instance.new, className)
			if ok then
				if nativeClass(inst) then REALV[p] = inst else inst:Destroy() end
			end
		end
		if isP(parent) then setParent(p, parent) end
		return p
	end,
	fromExisting = function(obj)
		return callP("Instance.fromExisting(" .. fmt(obj) .. ")", "clone")
	end,
})

RandomMT.__index = RandomMT
RandomMT.__metatable = "The metatable is locked"
RandomMT.__type = "Random"
do

local band, bor, bxor, lsh, rsh, rrot = bit32.band, bit32.bor, bit32.bxor, bit32.lshift, bit32.rshift, bit32.rrotate
local MUL = { 0x7F2D, 0x4C95, 0xF42D, 0x5851 }
local function pcgStep(st)
	local h, l = st.h, st.l
	local a = { band(l, 0xFFFF), rsh(l, 16), band(h, 0xFFFF), rsh(h, 16) }
	local r0 = a[1] * MUL[1]
	local r1 = a[1] * MUL[2] + a[2] * MUL[1] + R.floor(r0 / 65536)
	local r2 = a[1] * MUL[3] + a[2] * MUL[2] + a[3] * MUL[1] + R.floor(r1 / 65536)
	local r3 = a[1] * MUL[4] + a[2] * MUL[3] + a[3] * MUL[2] + a[4] * MUL[1] + R.floor(r2 / 65536)
	local nl = (r0 % 65536) + (r1 % 65536) * 65536 + 105
	local carry = nl >= 4294967296 and 1 or 0
	st.l = nl % 4294967296
	st.h = ((r2 % 65536) + (r3 % 65536) * 65536 + carry) % 4294967296
end
local function nextWord(st)
	local h, l = st.h, st.l
	pcgStep(st)
	local xh = bxor(h, rsh(h, 18))
	local xl = bxor(l, bor(rsh(l, 18), lsh(h, 14)))
	return rrot(bor(rsh(xl, 27), lsh(xh, 5)), rsh(h, 27))
end
local function seedState(st, seed)
	local hi, lo = 0, 0
	if seed ~= seed then
		hi = 0x80000000
	elseif R.type(seed) == "number" and seed > -9007199254740992 and seed < 9007199254740992 then
		local v = R.floor(seed)
		local m = v < 0 and -v or v
		hi, lo = R.floor(m / 4294967296), m % 4294967296
		if v < 0 then
			lo = (4294967296 - lo) % 4294967296
			hi = (4294967295 - hi + (lo == 0 and 1 or 0)) % 4294967296
		end
	end
	st.h, st.l = 0, 0
	pcgStep(st)
	local nl = st.l + lo
	st.l = nl % 4294967296
	st.h = (st.h + hi + (nl >= 4294967296 and 1 or 0)) % 4294967296
	pcgStep(st)
end
local f32buf = buffer.create(4)
local function f32(x)
	buffer.writef32(f32buf, 0, x)
	return buffer.readf32(f32buf, 0)
end

local RSTATE = R.setmetatable({}, { __mode = "k" })

local function scaleWord(w, range)
	local a = R.floor(w / 65536) * range
	local b = (w % 65536) * range
	return R.floor((a + R.floor(b / 65536)) / 65536)
end
local function rtype(v)
	if RSTATE[v] then return "Random" end
	if isP(v) then return INFO[v].tname end
	return R.typeof(v)
end
local function numArg(v, i, fname)
	if v == nil then
		R.error(R.fmt("missing argument #%d%s (number expected)", i, fname and (" to '" .. fname .. "'") or ""), 5)
	end
	local n = R.tonumber(v)
	if R.type(v) ~= "number" and not (R.type(v) == "string" and n) then
		R.error(R.fmt("invalid argument #%d%s (number expected, got %s)", i, fname and (" to '" .. fname .. "'") or "", rtype(v)), 5)
	end
	return n
end
local RMETHODS = {}
local makeRandom
function RMETHODS.NextNumber(st, n, a, b)
	if n ~= 0 and n ~= 2 then R.error("Random:NextNumber requires 0 or 2 arguments", 4) end
	if n == 2 then a, b = numArg(a, 2), numArg(b, 3) end
	local lo = nextWord(st)
	local hi = nextWord(st)
	local u = hi * 2 ^ -32 + lo * 2 ^ -64
	if n == 0 then return u end
	if a > b then a, b = b, a end
	return a + (b - a) * u
end
function RMETHODS.NextInteger(st, n, a, b)
	a, b = numArg(a, 2), numArg(b, 3)
	a, b = R.floor(a), R.floor(b)
	if a > b then a, b = b, a end
	local range = b - a + 1
	if range <= 4294967294 then
		return a + scaleWord(nextWord(st), range)
	end

	local lo = nextWord(st)
	local hi = nextWord(st)
	local x = { lo % 65536, R.floor(lo / 65536), hi % 65536, R.floor(hi / 65536) }
	local y, rr = {}, range % 18446744073709551616
	for i = 1, 4 do y[i] = rr % 65536; rr = R.floor(rr / 65536) end
	local limbs = {}
	for k = 1, 8 do limbs[k] = 0 end
	for i = 1, 4 do
		for j = 1, 4 do limbs[i + j - 1] += x[i] * y[j] end
	end
	for k = 1, 7 do
		limbs[k + 1] += R.floor(limbs[k] / 65536)
		limbs[k] %= 65536
	end
	return a + ((limbs[8] * 65536 + limbs[7]) * 65536 + limbs[6]) * 65536 + limbs[5]
end
function RMETHODS.NextUnitVector(st)
	local lo = nextWord(st)
	local hi = nextWord(st)
	local z = f32(f32(2 * f32(hi * 2 ^ -32)) - 1)
	local r = f32(math.sqrt(f32(1 - f32(z * z))))
	local th = f32(f32(2 * math.pi) * f32(lo * 2 ^ -32))
	return E.Vector3.new(f32(r * f32(math.cos(th))), f32(r * f32(math.sin(th))), z)
end
function RMETHODS.Shuffle(st, n, t)
	if R.type(t) ~= "table" then
		R.error(R.fmt("invalid argument #2 (table expected, got %s)", t == nil and "nil" or rtype(t)), 4)
	end
	if table.isfrozen(t) then R.error("attempt to modify a readonly table", 0) end
	for i = #t, 2, -1 do
		local j = 1 + scaleWord(nextWord(st), i)
		t[i], t[j] = t[j], t[i]
	end
end
function RMETHODS.Clone(st)
	return makeRandom({ h = st.h, l = st.l })
end
local R_INDEX, R_EQ, R_TOSTRING, R_NEWINDEX
R_INDEX = function(self, k)
	if R.type(k) ~= "string" then
		R.error(R.fmt("invalid argument #2 (string expected, got %s)", rtype(k)), 2)
	end
	local m = RMETHODS[k]
	if not m then R.error(k .. " is not a valid member of Random", 0) end
	local f = tramp(function(...)
		local nargs = R.select("#", ...)
		local obj = ...
		if nargs == 0 then R.error(R.fmt("missing argument #1 to '%s' (Random expected)", k), 3) end
		local st = RSTATE[obj]
		if not st then R.error(R.fmt("invalid argument #1 to '%s' (Random expected, got %s)", k, rtype(obj)), 3) end
		return m(st, nargs - 1, R.select(2, ...))
	end)
	CFUNCS[f] = true
	CNAME[f] = k
	return f
end
R_NEWINDEX = function(_, k) R.error(R.tostring(k) .. " is not a valid member of Random", 0) end
R_EQ = function(a, b)
	local x, y = RSTATE[a], RSTATE[b]
	return x ~= nil and y ~= nil and x.h == y.h and x.l == y.l
end
R_TOSTRING = function() return "Random" end
function makeRandom(st)
	local p = R.newproxy(true)
	local mt = R.getmetatable(p)
	mt.__index = R_INDEX
	mt.__newindex = R_NEWINDEX
	mt.__eq = R_EQ
	mt.__tostring = R_TOSTRING
	mt.__type = "Random"
	mt.__metatable = "The metatable is locked"
	RSTATE[p] = st
	return p
end
RANDOM_STATE = RSTATE
local function newRandom(...)
	local seed = ...
	if seed == nil then
		seed = R.floor(os.clock() * 1e6)
	else
		local n = R.tonumber(seed)
		if R.type(seed) ~= "number" and not (R.type(seed) == "string" and n) then
			R.error(R.fmt("invalid argument #1 to 'new' (number expected, got %s)", rtype(seed)), 3)
		end
		seed = n
	end
	local st = { h = 0, l = 0 }
	seedState(st, seed)
	return makeRandom(st)
end
E.Random = table.freeze({ new = nativeFn("Random.new", newRandom) })
if NATIVE and not CFG.fake_random then E.Random = REAL_G.Random end
if CFG.random_probe then
	local inner = E.Random
	E.Random = R.setmetatable({}, { __index = function(_, k) R.print("[Random.index]", R.tostring(k)); return inner[k] end,
		__iter = function() R.print("[Random.iter]"); return R.next, inner end })
end
end

do
	local VMT = R.getmetatable(vector.create(0, 0, 0))
	if not NATIVE and R.type(VMT) == "table" and not table.isfrozen(VMT) then
		local vdot, vcross, vmag, vnorm, vlerp, vangle = vector.dot, vector.cross, vector.magnitude,
			vector.normalize, vector.lerp, vector.angle
		local fbuf = buffer.create(4)
		local function f32(x)
			buffer.writef32(fbuf, 0, x)
			return buffer.readf32(fbuf, 0)
		end
		local function vtype(v)
			if R.type(v) == "vector" then return "Vector3" end
			if v == nil then return "nil" end
			if isP(v) then return INFO[v].tname end
			return R.typeof(v)
		end
		local function isVec(v) return R.type(v) == "vector" end
		local function isVecP(v) return isP(v) and INFO[v].tname == "Vector3" end

		local function vecArg(v, i, n)
			if isVec(v) then return v end
			if i > n then R.error(R.fmt("missing argument #%d (Vector3 expected)", i), 5) end
			R.error(R.fmt("invalid argument #%d (Vector3 expected, got %s)", i, vtype(v)), 5)
		end
		local function numArg(v, i, n)
			local x = R.tonumber(v)
			if R.type(v) == "number" or (R.type(v) == "string" and x) then return x end
			if i > n then R.error(R.fmt("missing argument #%d (number expected)", i), 5) end
			R.error(R.fmt("invalid argument #%d (number expected, got %s)", i, vtype(v)), 5)
		end
		local function fuzzy(a, n, b, eps)
			b = vecArg(b, 2, n)
			eps = R.type(eps) == "number" and eps or 1e-5
			for _, c in { "x", "y", "z" } do
				local x, y = a[c], b[c]
				local m = math.max(1, math.abs(x), math.abs(y))
				if not (math.abs(x - y) <= eps * m) then return false end
			end
			return true
		end
		local function minmax(f)
			return function(a, n, ...)
				local args = { ... }
				if n < 2 then vecArg(nil, 2, n) end
				for i = 1, n - 1 do vecArg(args[i], i + 1, n) end
				return f(a, ...)
			end
		end
		local VMETHODS = {
			Dot = function(a, n, b) return vdot(a, vecArg(b, 2, n)) end,
			Cross = function(a, n, b) return vcross(a, vecArg(b, 2, n)) end,
			Lerp = function(a, n, b, t) return vlerp(a, vecArg(b, 2, n), numArg(t, 3, n)) end,
			FuzzyEq = fuzzy,
			Angle = function(a, n, b, axis)
				b = vecArg(b, 2, n)
				if axis ~= nil then return f32(vangle(a, b, vecArg(axis, 3, n))) end
				return f32(vangle(a, b))
			end,
			Abs = function(a) return vector.abs(a) end,
			Floor = function(a) return vector.floor(a) end,
			Ceil = function(a) return vector.ceil(a) end,
			Sign = function(a) return vector.sign(a) end,
			Max = minmax(vector.max),
			Min = minmax(vector.min),
		}
		VMETHODS.lerp = VMETHODS.Lerp
		VMETHODS.isClose = fuzzy
		local VPROPS = {
			Magnitude = vmag, magnitude = vmag, Unit = vnorm, unit = vnorm,
			X = function(v) return v.x end, Y = function(v) return v.y end, Z = function(v) return v.z end,
		}
		VPROPS.x, VPROPS.y, VPROPS.z = VPROPS.X, VPROPS.Y, VPROPS.Z
		VMT.__index = function(self, k)
			if R.type(k) ~= "string" then
				R.error(R.fmt("invalid argument #2 (string expected, got %s)", vtype(k)), 2)
			end
			local prop = VPROPS[k]
			if prop then return prop(self) end
			local m = VMETHODS[k]
			if not m then R.error(k .. " is not a valid member of Vector3", 0) end
			local f = tramp(function(...)
				local n = R.select("#", ...)
				local obj = ...
				if not isVec(obj) then
					if n == 0 then R.error(R.fmt("missing argument #1 to '%s' (Vector3 expected)", k), 3) end
					R.error(R.fmt("invalid argument #1 to '%s' (Vector3 expected, got %s)", k, vtype(obj)), 3)
				end

				for i = 2, n do
					if isVecP((R.select(i, ...))) then
						local sp = exprP(fmt(obj), "Vector3")
						return sp[k](sp, R.select(2, ...))
					end
				end
				return m(obj, n, R.select(2, ...))
			end)
			CFUNCS[f] = true
			CNAME[f] = k
			return f
		end
		VMT.__newindex = function(_, k)
			if VPROPS[k] then R.error(R.tostring(k) .. " cannot be assigned to", 0) end
			R.error(R.tostring(k) .. " is not a valid member of Vector3", 0)
		end
		VMT.__metatable = "The metatable is locked"
		table.freeze(VMT)
	end
end
E.Enum = newP({ kind = "name", name = "Enum", tname = "Enums" })
enumRoot = E.Enum

local function markC(tbl, seen)
	seen = seen or {}
	if seen[tbl] then return end
	seen[tbl] = true
	for k, v in R.pairs(tbl) do
		if R.type(v) == "function" then
			CFUNCS[v] = true
			if CNAME[v] == nil and R.type(k) == "string" then CNAME[v] = k end
		elseif R.type(v) == "table" and v ~= ENV then
			markC(v, seen)
		end
	end
end
local function isC(f)
	if CFUNCS[f] then return true end
	return R.type(f) == "function" and debug.info(f, "s") == "[C]"
end

local EXECUTOR = CFG.executor or "Wave"
E.identifyexecutor = function()
	comment("identifyexecutor() -> " .. quote(EXECUTOR))
	return EXECUTOR, "1.0.0"
end
E.getexecutorname = function(...) return E.identifyexecutor(...) end
E.iscclosure = function(f)
	if CFG.trace or CFG.ptrace then R.print("[iscclosure]", f, isC(f)) end
	if isP(f) then return true end
	return isC(f)
end
E.islclosure = function(f)
	if CFG.trace or CFG.ptrace then R.print("[islclosure]", f, isC(f)) end
	if isP(f) then return false end
	return R.type(f) == "function" and not isC(f)
end
E.isexecutorclosure = function(f) return false end
E.checkclosure = function(...) return E.isexecutorclosure(...) end
E.newcclosure = function(f)
	CFUNCS[f] = true
	return f
end
E.newlclosure = function(f) return f end
E.clonefunction = function(f) return f end
E.checkcaller = function() return true end

do
	local hooked = R.setmetatable({}, { __mode = "k" })
	E.isfunctionhooked = function(f) return hooked[f] == true end
	E.restorefunction = function(f) hooked[f] = nil end
	E.hookfunction = function(target, repl)
		emit({ text = "hookfunction(" .. fmt(target) .. ", " .. fmt(repl) .. ")" })
		if R.type(target) == "function" then hooked[target] = true end
		return target
	end
end
E.ishooked = function(...) return E.isfunctionhooked(...) end
E.replaceclosure = function(...) return E.hookfunction(...) end
E.hookmetamethod = function(obj, method, repl)
	emit({ text = "hookmetamethod(" .. fmt(obj) .. ", " .. fmt(method) .. ", " .. fmt(repl) .. ")" })
	return function(...) return nil end
end

do

	local function upval(f, n) return nil end
	local function const(f, n) return nil end
	E.getupvalues = function(f)
		emit({ text = "getupvalues(" .. fmt(f) .. ")" })
		local out = {}
		if R.type(f) == "function" then
			for n = 1, 64 do
				local name, v = upval(f, n)
				if not name then break end
				out[n] = name
			end
		end
		return out
	end
	E.getupvalue = function(f, n)
		local name, v = upval(f, n)
		if name then emit({ text = "getupvalue(" .. fmt(f) .. ", " .. tostring(n) .. ") = " .. quote(name) }) end
		return name, v
	end
	E.setupvalue = function(f, n, v)
		local name = upval(f, n)
		emit({ text = "setupvalue(" .. fmt(f) .. ", " .. tostring(n) .. ", " .. fmt(v) .. ")" })
		return name
	end
	E.getconstants = function(f)
		emit({ text = "getconstants(" .. fmt(f) .. ")" })
		local out = {}
		if R.type(f) == "function" then
			for n = 1, 256 do
				local v = const(f, n)
				if v == nil then break end
				out[n] = v
			end
		end
		return out
	end
	E.getconstant = function(f, n)
		local v = const(f, n)
		emit({ text = "getconstant(" .. fmt(f) .. ", " .. tostring(n) .. ")" })
		return v
	end
	E.setconstant = function() end

	local PERMISSIVE = {}
	PERMISSIVE.__index = function(t, k)
		local sub = R.setmetatable({ __path = (t.__path or "settings") .. "." .. k }, PERMISSIVE)
		R.rawset(t, k, sub)
		return sub
	end
	PERMISSIVE.__newindex = function(t, k, v)
		emit({ text = (t.__path or "settings") .. "." .. k .. " = " .. fmt(v) })
		R.rawset(t, k, v)
	end
	local SETTINGS
	E.settings = function()
		if not SETTINGS then
			SETTINGS = R.setmetatable({ __path = "settings" }, PERMISSIVE)
			emit({ text = "settings()" })
		end
		return SETTINGS
	end
	local USERSETTINGS
	E.UserSettings = function()
		if not USERSETTINGS then
			USERSETTINGS = R.setmetatable({ __path = "UserSettings" }, PERMISSIVE)
			emit({ text = "UserSettings()" })
		end
		return USERSETTINGS
	end

	E.makesecret = function()
		local s = {}
		for _ = 1, 32 do
			s[#s + 1] = REAL_G.string.char(REAL_G.math.random(48, 57))
		end
		local out = R.concat(s)
		emit({ text = "makesecret()" })
		return out
	end
	E.protect_gui = function(g) return g end
	E.syn = {
		protect_gui = function(g) return g end,
		protect_function = function(f) return f end,
		library = { enabled = true },
	}
end
E.getnamecallmethod = function() return "FireServer" end
E.setreadonly = function() end
E.makewritable = function() end
E.makereadonly = function() end
E.isreadonly = function(t) return table.isfrozen(t) end
E.setclipboard = function(s) emit({ text = "setclipboard(" .. fmt(s) .. ")" }) end
E.toclipboard = function(...) return E.setclipboard(...) end
E.fireproximityprompt = function(...) emit({ text = "fireproximityprompt(" .. fmtArgs(...) .. ")" }) end
E.firetouchinterest = function(...) emit({ text = "firetouchinterest(" .. fmtArgs(...) .. ")" }) end
E.fireclickdetector = function(...) emit({ text = "fireclickdetector(" .. fmtArgs(...) .. ")" }) end
E.isfile = function(p) comment("isfile(" .. fmt(p) .. ") -> false"); return false end
E.isfolder = function(p) comment("isfolder(" .. fmt(p) .. ") -> false"); return false end
E.readfile = function(p) return callP("readfile(" .. fmt(p) .. ")", "contents", "string") end
E.writefile = function(p, c) emit({ text = "writefile(" .. fmt(p) .. ", " .. fmt(c) .. ")" }) end
E.appendfile = function(p, c) emit({ text = "appendfile(" .. fmt(p) .. ", " .. fmt(c) .. ")" }) end
E.makefolder = function(p) emit({ text = "makefolder(" .. fmt(p) .. ")" }) end
E.delfile = function(p) emit({ text = "delfile(" .. fmt(p) .. ")" }) end
E.listfiles = function(p) return {} end
E.getconnections = function(sig) return {} end
E.gethui = function() return callP("gethui()", "hui") end
E.cloneref = function(x) return x end
E.compareinstances = function(a, b) return a == b end
E.getcustomasset = function(p) return "rbxasset://" .. R.tostring(p) end
E.queue_on_teleport = function(s) emit({ text = "queue_on_teleport(" .. fmt(s) .. ")" }) end
E.queueonteleport = function(...) return E.queue_on_teleport(...) end
local function httpRequest(label)
	return function(...)
		local opts = ...

		if R.type(opts) ~= "table" then
			argError(1, R.match(label, "([%w_]+)$"), "table", ...)
		end
		if R.type(opts.Url) == "string" then remember(urls, opts.Url) end
		return callP(label .. "(" .. fmt(opts) .. ")", "response", "table")
	end
end
E.request = httpRequest("request")
E.http_request = httpRequest("http_request")
E.http = { request = httpRequest("http.request") }
E.getrawmetatable = function(x)
	if GENVNAME[x] then return nil end
	if isP(x) then
		return { __index = function() end, __newindex = function() end, __namecall = function() end }
	end
	return R.getmetatable(x)
end
E.setrawmetatable = function(x, mt) return x end
E.getgc = function() return {} end
E.getreg = function() return {} end
E.getloadedmodules = function() return {} end
E.getrunningscripts = function() return {} end
E.getscripts = function() return {} end
E.getinstances = function() return {} end
E.getnilinstances = function() return {} end
E.getscriptclosure = function() return function() end end
E.getsenv = function() return {} end
E.getcallingscript = function() return E.script end
E.getthreadidentity = function() return 8 end
E.getidentity = function(...) return E.getthreadidentity(...) end
E.getthreadcontext = function(...) return E.getthreadidentity(...) end
E.setthreadidentity = function() end
E.setidentity = function() end
E.lz4compress = function(s) return s end
E.lz4decompress = function(s) return s end
E.crypt = { base64encode = function(s) return s end, base64decode = function(s) return s end }
E.base64_encode = E.crypt.base64encode
E.base64_decode = E.crypt.base64decode
E.Drawing = { new = function(kind) return callP("Drawing.new(" .. fmt(kind) .. ")", R.type(kind) == "string" and kind or "drawing") end }
E.isrbxactive = function() return true end
E.isgameactive = function(...) return E.isrbxactive(...) end

local realInfo = debug.info
local HARNESS_SRC = realInfo(1, "s")
local fakeDebug = {}
for k, v in R.pairs(debug) do fakeDebug[k] = v end

local function isHarness(f)
	return R.type(f) == "function" and realInfo(f, "s") == HARNESS_SRC
end

local function visibleStack(th, from)
	local frames = {}
	local lvl = from
	while true do
		local f
		if th then f = realInfo(th, lvl, "f") else f = realInfo(lvl, "f") end
		if f == nil then

			local src
			if th then src = realInfo(th, lvl, "s") else src = realInfo(lvl, "s") end
			if src == nil then break end
		end
		R.insert(frames, { f = f, lvl = lvl })
		lvl += 1
	end
	local out = {}
	local i = 1
	while i <= #frames do
		local fr = frames[i]
		local harness = isHarness(fr.f)
		if not harness and realInfo(fr.f or print, "s") == "[C]" then

			local j = i
			while j <= #frames and not isHarness(frames[j].f) and realInfo(frames[j].f or print, "s") == "[C]" do
				j += 1
			end
			if j <= #frames and isHarness(frames[j].f) then
				i = j
				harness = true
				fr = frames[i]
			end
		end
		if harness then

			while i + 1 <= #frames and isHarness(frames[i + 1].f) do
				i += 1
			end
			R.insert(out, { f = frames[i].f, fake = true, lvl = frames[i].lvl })
		else
			R.insert(out, { f = fr.f, lvl = fr.lvl })
		end
		i += 1
	end
	return out
end

local function fakeFields(f, opts)
	local out = {}
	for ch in string.gmatch(opts, ".") do
		if ch == "s" then R.insert(out, "[C]")
		elseif ch == "l" then R.insert(out, -1)
		elseif ch == "n" then R.insert(out, CNAME[f] or "")
		elseif ch == "a" then R.insert(out, 0); R.insert(out, true)
		elseif ch == "f" then R.insert(out, f) end
	end
	return R.unpack(out)
end

local info0
fakeDebug.info = function(a, b, c)
	if CFG.ptrace then
		local r = table.pack(info0(a, b, c, 1))
		local t = {}
		for i = 1, r.n do t[i] = R.tostring(r[i]) end
		R.print("[debug.info]", R.type(a) == "function" and (CNAME[a] or FNAME[a] or R.tostring(a)) or R.tostring(a), b, c, "->", R.concat(t, ", ", 1, r.n))
		return R.unpack(r, 1, r.n)
	end
	return info0(a, b, c, 1)
end
CFUNCS[fakeDebug.info] = true
CNAME[fakeDebug.info] = "info"
function info0(a, b, c, extra)
	if R.type(a) == "function" then
		if CFUNCS[a] or isHarness(a) then return fakeFields(a, b) end
		return realInfo(a, b)
	end
	local th, level, opts = nil, a, b
	if R.type(a) == "thread" then th, level, opts = a, b, c end
	if R.type(level) ~= "number" then
		if CFG.debug_stack and isP(a) then R.print("[debug.info on proxy]", INFO[a].kind, INFO[a].key, INFO[a].hint) end
		return realInfo(a, b, c)
	end

	local stack = visibleStack(th, th and 0 or 3 + (extra or 0))
	local fr = stack[th and level + 1 or level]
	if CFG.debug_stack then
		local parts = {}
		for i, x in stack do
			parts[i] = (x.fake and "*" or "") .. R.tostring(CNAME[x.f] or x.f) .. "@" .. R.tostring(realInfo(x.f or print, "s"))
			if i > 6 then break end
		end
		local raw = {}
		for l = 2, 9 do
			local f = realInfo(l, "f")
			raw[#raw + 1] = R.tostring(CNAME[f] or f) .. "@" .. R.tostring(realInfo(l, "s"))
		end
		R.print("[stack] level", level, opts, "->", R.concat(parts, " | "), "\n   raw:", R.concat(raw, " | "))
	end
	if level == 0 and not th then
		return fakeFields(fakeDebug.info, opts)
	end
	if not fr then return nil end
	if fr.fake then return fakeFields(fr.f, opts) end
	if th then return realInfo(th, fr.lvl, opts) end

	return realInfo(fr.lvl - 1, opts)
end

fakeDebug.traceback = function(a, b, c)
	local tb = debug.traceback(a, b, c)
	if R.type(tb) ~= "string" then return tb end
	local keep = {}
	for line in string.gmatch(tb, "[^\n]+") do
		if not R.find(line, HARNESS_SRC, 1, true) then R.insert(keep, line) end
	end
	return R.concat(keep, "\n")
end

do
	local memcat = "Default"
	if fakeDebug.profilebegin == nil then fakeDebug.profilebegin = function(label)
		if R.type(label) ~= "string" then R.error("invalid argument #1 to 'profilebegin' (string expected, got " .. R.typeof(label) .. ")", 2) end
	end end
	if fakeDebug.profileend == nil then fakeDebug.profileend = function() end end
	if fakeDebug.setmemorycategory == nil then fakeDebug.setmemorycategory = function(tag)
		if R.type(tag) ~= "string" then R.error("invalid argument #1 to 'setmemorycategory' (string expected, got " .. R.typeof(tag) .. ")", 2) end
		local old = memcat
		memcat = tag
		return old
	end end
	if fakeDebug.resetmemorycategory == nil then fakeDebug.resetmemorycategory = function() memcat = "Default" end end
	if fakeDebug.getmemorycategory == nil then fakeDebug.getmemorycategory = function() return memcat end end
end
E.debug = fakeDebug

E.getmetatable = function(...)
	if GENVNAME[(...)] then return nil end
	return R.getmetatable(...)
end
CFUNCS[E.getmetatable] = true
CNAME[E.getmetatable] = "getmetatable"

if CFG.oplog then
	local ring, pos, N = {}, 0, CFG.oplog
	E.__OPLOG = function(loop, op, pc)
		pos += 1
		ring[pos % N] = loop .. " op=" .. op .. " pc=" .. pc
	end
	E.__SEEN = {}
	do
		local co = {}
		for k, f in R.pairs(coroutine) do
			co[k] = function(...)
				local res = table.pack(f(...))
				local a = {}
				for i = 1, R.select("#", ...) do a[i] = E.__NAME((R.select(i, ...))) end
				local r = {}
				for i = 1, res.n do r[i] = E.__NAME(res[i]) end
				pos += 1
				ring[pos % N] = "CO coroutine." .. k .. "(" .. R.concat(a, ", ") .. ") -> " .. R.concat(r, ", ")
				return R.unpack(res, 1, res.n)
			end
		end
		E.coroutine = co
	end
	local PIDS, npid = {}, 0
	E.__OPL = function(loop, op, pc, proto)
		local id = PIDS[proto]
		if not id then
			npid += 1
			id = npid
			PIDS[proto] = id
			pos += 1
			ring[pos % N] = "NEWPROTO P" .. id .. " " .. R.tostring(proto)
		end
		pos += 1
		ring[pos % N] = "P" .. id .. " L" .. loop .. " op" .. op .. " pc" .. pc
	end
	E.__OPV = function(v, pc)
		pos += 1
		ring[pos % N] = "  = " .. E.__NAME(v)
	end
	local names = nil
	E.__NAME = function(v)
		if not names then
			names = {}
			for k, x in R.pairs(E) do
				if R.type(x) == "function" then names[x] = k
				elseif R.type(x) == "table" and x ~= ENV then
					for k2, y in R.pairs(x) do
						if R.type(y) == "function" then names[y] = k .. "." .. R.tostring(k2) end
					end
				end
			end
		end
		if names[v] then return names[v] end
		local t = R.type(v)
		if t == "string" then return R.fmt("%q", R.sub(v, 1, 80)) end
		if isP(v) then return "<proxy " .. R.tostring(INFO[v].name or INFO[v].hint) .. ">" end
		return R.tostring(v)
	end
	E.__DUMP = function(label, t, depth)
		depth = depth or 0
		local function d(v, lvl)
			if R.type(v) ~= "table" or lvl > 2 then return E.__NAME(v) end
			local parts = {}
			for k, x in R.pairs(v) do
				R.insert(parts, "[" .. E.__NAME(k) .. "]=" .. d(x, lvl + 1))
				if #parts > 80 then break end
			end
			return "{" .. R.concat(parts, ", ") .. "}"
		end
		R.print("[dump]", label, d(t, 0))
	end
	E.__OPDUMP = function()
		for i = R.max(1, pos - N + 1), pos do
			R.print(ring[i % N])
		end
	end
end

if CFG.flip_probe then
	E.__P = { n = 0 }
end

if CFG.inline_probe then
	E.__R = table.create(1e6)
	E.__P = { n = 0 }
	E.__OPDUMP = function()
		local names = {}
		for k, x in R.pairs(E) do
			if R.type(x) == "function" then names[x] = k
			elseif R.type(x) == "table" and x ~= ENV then
				for k2, y in R.pairs(x) do
					if R.type(y) == "function" then names[y] = k .. "." .. R.tostring(k2) end
				end
			end
		end
		local function nm(v)
			if names[v] then return names[v] end
			if R.type(v) == "string" then return R.fmt("%q", R.sub(v, 1, 80)) end
			if isP(v) then
				local chain, q, guard = {}, v, 0
				while q and guard < 12 do
					guard += 1
					local qi = INFO[q]
					R.insert(chain, 1, R.tostring(qi.name or qi.key or qi.hint or qi.kind))
					q = qi.parent
				end
				return "<proxy " .. R.concat(chain, ".") .. ">"
			end
			return R.tostring(v)
		end
		local rr = E.__R
		for i = R.max(1, #rr - (CFG.dump_last or 1500000)), #rr do
			local e = rr[i]
			if R.type(e) == "number" then
				local pc = e % 65536
				local rest = (e - pc) / 65536
				local op = rest % 256
				rest = (rest - op) / 256
				local loop = rest % 16
				local pid = (rest - loop) / 16
				R.print("P" .. pid .. " L" .. loop .. " op" .. op .. " pc" .. pc)
			else
				R.print("  = " .. nm(e[1]))
			end
		end
	end
end

if CFG.co_log then
	local co = {}
	for k, f in R.pairs(coroutine) do co[k] = f end
	co.resume = function(...)
		local res = table.pack(coroutine.resume(...))
		R.print("[co.resume]", R.unpack(res, 1, res.n))
		return R.unpack(res, 1, res.n)
	end
	E.coroutine = co
end

E.__PID = { n = 0 }
E.__ENT = { n = 0 }
E.__SKIPP = {}
E.__PF = R.setmetatable({}, { __mode = "k" })
E.__PLAST = {}
if CFG.fold ~= false then
	CHAIN.pf, CHAIN.pid, CHAIN.plast = E.__PF, E.__PID, E.__PLAST
end
for _, pid in CFG.skip_protos or {} do E.__SKIPP[pid] = true end

if CFG.spin then
	local sw = { n = 0, step = 1048576 }
	CHAIN.spinWatch = sw
	local idle, lastS, lastId = 0, -1, -1
	sw.f = function()
		sw.n = 0

		if CFG.heartbeat and R.clock() - (CFG._hb or START) > CFG.heartbeat then
			CFG._hb = R.clock()
			R.print("\0HB\n" .. R.rep(" ", 16384))
		end
		if stmtCount ~= lastS or nextId ~= lastId then
			idle, lastS, lastId = 0, stmtCount, nextId
			return
		end
		if CHAIN.decodeUntil then

			if R.clock() > CHAIN.decodeUntil then
				ABORT_REASON = "constant decode took too long"
				R.error(ABORT, 0)
			end
			return
		end
		idle += 1
		if idle >= CFG.spin then
			ABORT_REASON = ABORT_REASON or "endless loop in the script's own code (no environment access)"
			checkBudget()
		end
	end
	E.__SPIN = sw
end

E.__PA = CFG.devirt and { n = 0 } or false
E.__PK = {}
if E.__PA then

	local orig = R.setmetatable({}, { __mode = "k" })
	CHAIN.paOrig = orig

	local nested = R.setmetatable({}, { __mode = "k" })
	local lazyKeys = R.setmetatable({}, { __mode = "k" })
	local holders = R.setmetatable({}, { __mode = "k" })
	local function numCopy(arr)
		local c, n = {}, 0
		for i, x in R.next, arr do
			if R.type(x) == "number" then c[i] = x; n += 1 end
		end
		return n > 0 and c or nil
	end
	local function snapNested(proto, w)
		if nested[w] == nil then
			if R.type(w) == "buffer" then
				local b = buffer.create(buffer.len(w))
				buffer.copy(b, 0, w)
				nested[w] = b
			else
				nested[w] = numCopy(w) or false
			end
		end
		return nested[w]
	end
	R.setmetatable(E.__PA, { __newindex = function(t, proto, v)
		R.rawset(t, proto, v)
		if R.type(proto) ~= "table" then return end
		local copy = {}
		for key, arr in R.next, proto do
			if R.type(arr) == "table" and arr ~= proto and not copy[arr] then
				local c = numCopy(arr)
				if arr ~= E and R.getmetatable(arr) ~= nil and lazyKeys[arr] == nil then

					local keys = {}
					for k in R.next, arr do keys[k] = true end
					lazyKeys[arr] = keys
					c = c or {}
				end
				if c then
					copy[arr] = c
				elseif arr ~= E and R.getmetatable(arr) == nil then

					for _, w in R.next, arr do
						if (R.type(w) == "table" and w ~= proto and w ~= arr and w ~= E and R.getmetatable(w) == nil)
							or R.type(w) == "buffer" then
							if snapNested(proto, w) then
								holders[proto] = holders[proto] or {}
								holders[proto][key] = arr
							end
						end
					end
				end
			end
		end
		orig[proto] = copy
	end })

	CHAIN.lazyLate = R.setmetatable({}, { __mode = "k" })
	local function restore(copy)
		for arr, c in R.next, copy do
			local keys = lazyKeys[arr]
			if keys and not CHAIN.lazyLate[arr] then
				local late = {}
				for k in R.next, arr do
					if not keys[k] then late[k] = true end
				end
				CHAIN.lazyLate[arr] = late
			end
			for i, x in R.next, c do R.rawset(arr, i, x) end
		end
	end

	CHAIN.unscramble = function()
		local fixed = 0
		local done, ran, size = {}, {}, {}
		for proto, copy in R.next, orig do
			local arrays, all = 0, true
			size[proto] = 0
			for arr, c in R.next, copy do
				if not lazyKeys[arr] then
					local n, same, huge = 0, 0, 0
					for i, x in R.next, c do
						n += 1
						local y = R.rawget(arr, i)
						if y == x then
							same += 1
						elseif R.type(y) == "number" and (y >= 16777216 or y <= -16777216) then
							huge += 1
						end
					end
					if same < n then ran[proto] = true end
					if n > size[proto] then size[proto] = n end
					if n >= 2 then arrays += 1 end

					if same > 0 and (same > n * 0.1 or huge < (n - same) * 0.8) then all = false end
				end
			end
			if all and arrays >= 2 then
				restore(copy)
				fixed += 1
				done[proto] = true
			end
		end

		local users = {}
		for proto, hs in R.next, holders do
			for key, arr in R.next, hs do
				users[arr] = users[arr] or {}
				users[arr][proto] = key
			end
		end
		for arr, set in R.next, users do
			local restored, live = 0, 0
			for p in R.next, set do
				if done[p] then restored += size[p] or 0 elseif ran[p] then live += size[p] or 0 end
			end
			if restored > 0 then
				local whole = restored >= live
				local view = nil
				for k, w in R.next, arr do
					local snap = nested[w]
					local changed = false
					if R.type(w) == "buffer" and snap then
						changed = buffer.tostring(w) ~= buffer.tostring(snap)
					elseif R.type(w) == "table" and snap then
						for i, x in R.next, snap do
							if R.rawget(w, i) ~= x then changed = true break end
						end
					end
					if changed and whole then
						if R.type(w) == "buffer" then
							buffer.copy(w, 0, snap)
						else
							for i, x in R.next, snap do R.rawset(w, i, x) end
						end
					elseif changed then
						local pristine
						if R.type(w) == "buffer" then
							pristine = buffer.create(buffer.len(snap))
							buffer.copy(pristine, 0, snap)
						else
							pristine = {}
							for i, x in R.next, w do pristine[i] = x end
							for i, x in R.next, snap do pristine[i] = x end
						end
						if not view then
							view = {}
							for k2, w2 in R.next, arr do view[k2] = w2 end
						end
						view[k] = pristine
					end
				end
				for p, key in R.next, set do
					if whole and ran[p] and not done[p] and orig[p] then
						restore(orig[p])
						done[p] = true
						fixed += 1
					elseif view and done[p] then
						R.rawset(p, key, view)
					end
				end
			end
		end
		return fixed
	end
end
do
	local LIBS = { "string", "table", "math", "bit32", "buffer", "coroutine", "utf8", "os", "debug", "task" }
	CHAIN.dumpProtos = function()
		local PA = E.__PA
		if not PA then return nil end
		CHAIN.unscrambled = CHAIN.unscramble()
		local fname = {}
		for k, v in R.next, E do
			if R.type(v) == "function" and R.type(k) == "string" then fname[v] = fname[v] or k end
		end
		for _, lib in R.ipairs(LIBS) do
			local t = R.rawget(E, lib)
			if R.type(t) == "table" then
				for k, v in R.next, t do
					if R.type(v) == "function" then fname[v] = fname[v] or (lib .. "." .. R.tostring(k)) end
				end
			end
		end
		local stop = { [E] = "ENV" }
		for _, lib in R.ipairs(LIBS) do
			local t = R.rawget(E, lib)
			if R.type(t) == "table" then stop[t] = lib end
		end
		local ids, queue, fids = {}, {}, {}
		local nfid = 0
		local function hex(s)
			return (R.gsub(s, ".", function(c) return R.fmt("%02x", R.byte(c)) end))
		end
		local function num(x)
			if x ~= x then return '{"num":"nan"}' end
			if x == R.huge then return '{"num":"inf"}' end
			if x == -R.huge then return '{"num":"-inf"}' end
			if x == 0 and 1 / x < 0 then return '{"num":"-0"}' end
			if x == R.floor(x) and x > -2 ^ 53 and x < 2 ^ 53 then return R.fmt("%d", x) end
			return R.fmt("%.17g", x)
		end
		local function enc(v)
			local t = R.type(v)
			if v == nil then return "null"
			elseif t == "boolean" then return v and "true" or "false"
			elseif t == "number" then return num(v)
			elseif t == "string" then return '{"s":"' .. hex(v) .. '"}'
			elseif t == "function" then
				if fname[v] then return '{"f":"' .. fname[v] .. '"}' end
				if not fids[v] then nfid += 1; fids[v] = nfid end

				local pf = R.rawget(E.__PF, v)
				if R.type(pf) == "table" then
					return '{"lf":' .. fids[v] .. ',"pf":' .. enc(pf) .. '}'
				end
				if CFG.lf_debug then
					local na, va = debug.info(v, "a")
					R.print("LFDBG", fids[v], debug.info(v, "l"), na, va, debug.info(v, "n"))
				end
				return '{"lf":' .. fids[v] .. '}'
			elseif t == "table" then
				if stop[v] then return '{"g":"' .. stop[v] .. '"}' end
				if not ids[v] then
					R.insert(queue, v)
					ids[v] = #queue
				end
				return '{"t":' .. ids[v] .. "}"
			elseif R.typeof(v) == "buffer" then
				return '{"b":"' .. hex(buffer.tostring(v)) .. '"}'
			elseif t == "vector" then
				return '{"vec":[' .. num(v.x) .. "," .. num(v.y) .. "," .. num(v.z) .. "]}"
			end

			local ok, src = R.pcall(function() return CHAIN.exprOf and CHAIN.exprOf(v) end)
			if not ok or R.type(src) ~= "string" then
				ok, src = R.pcall(R.tostring, v)
			end
			return '{"u":"' .. R.typeof(v) .. '","src":"' .. (ok and R.type(src) == "string" and hex(src) or "") .. '"}'
		end

		local forced = {}
		local fstats = { calls = 0, got = 0, t0 = R.clock() }
		CHAIN.forceStats = fstats
		local byseq = {}
		for proto, cap in R.next, PA do
			if R.type(cap) == "table" and cap.__seq then
				byseq[cap.__seq] = R.setmetatable({ self = proto }, { __index = cap })
			end
		end

		local snapTabs, snapBufs = {}, {}
		if R.type(CFG.force_req) == "string" then
			local q = {}
			for proto, cap in R.next, PA do
				if R.type(cap) == "table" then
					R.insert(q, cap)
					R.insert(q, proto)
				end
			end
			local qi = 1
			while qi <= #q do
				local t = q[qi]
				qi += 1
				if not snapTabs[t] and not stop[t] then
					local copy = {}
					for k, v in R.next, t do
						copy[k] = v
						if R.type(v) == "table" then
							R.insert(q, v)
						elseif R.typeof(v) == "buffer" and not snapBufs[v] then
							snapBufs[v] = buffer.tostring(v)
						end
					end
					snapTabs[t] = copy
				end
			end
		end

		local function applyBufs(bufs)
		local bufRestore = {}
		if R.type(bufs) == "string" then
			for spec in string.gmatch(bufs, "[^;]+") do
				local head = string.match(spec, "^[^/]+")
				local v, si = nil, 0
				for st in string.gmatch(head, "[^,]+") do
					local k = R.tonumber(st) or st
					si += 1
					if si == 1 then v = byseq[k]
					elseif si == 2 and R.type(v) == "table" then v = v[k]
					elseif R.type(v) == "table" then v = R.rawget(v, k)
					else v = nil end
				end
				if R.type(v) == "table" then
					for k, val in string.gmatch(spec, "/=(%-?%d+):([^/]+)") do
						k = R.tonumber(k)
						R.insert(bufRestore, { v, k, R.rawget(v, k), true })
						R.rawset(v, k, R.tonumber(val))
						fstats.bufs = (fstats.bufs or 0) + 1
					end
				elseif R.typeof(v) == "buffer" then
					for off, hx in string.gmatch(spec, "/(%d+):(%x+)") do
						off = R.tonumber(off)
						local n = #hx // 2
						if off + n <= buffer.len(v) then
							R.insert(bufRestore, { v, off, buffer.readstring(v, off, n) })
							fstats.bufs = (fstats.bufs or 0) + 1
							for j = 0, n - 1 do
								buffer.writeu8(v, off + j, R.tonumber(string.sub(hx, 2 * j + 1, 2 * j + 2), 16))
							end
						end
					end
				end
			end
		end
		return bufRestore
		end
		local function revertBufs(bufRestore)
			for i = #bufRestore, 1, -1 do
				local r = bufRestore[i]
				if r[4] then R.rawset(r[1], r[2], r[3]) else buffer.writestring(r[1], r[2], r[3]) end
			end
		end
		local bufRestore = applyBufs(CFG.force_buf)

		local function decodeStart(f, ...)
			CHAIN.decodeUntil = R.clock() + (CFG.decode_limit or 10)
			return f(...)
		end
		local abortBefore
		local function decodeGuard(...)
			CHAIN.decodeUntil = nil
			ABORT_REASON = abortBefore
			return ...
		end
		local function slot(v, k) return v[k] end
		local function decodeSlot(v, k)
			abortBefore = ABORT_REASON
			return decodeGuard(R.pcall(decodeStart, slot, v, k))
		end
		local function decodePath(path, derivedCache, forced)
			local steps, ovs, toks = {}, {}, {}
			for st in string.gmatch(path, "[^,]+") do
				R.insert(toks, st)
				local a, ov = string.match(st, "^(%-?%d+)@(%-?[%d%.e]+)$")
				if a then
					ovs[#steps + 1] = R.tonumber(ov)
					st = a
				end
				R.insert(steps, R.tonumber(st) or st)
			end
			local derived = false
			local v = byseq[steps[1]]
			local prefix = toks[1]
			for si = 2, #steps do
				prefix ..= "," .. toks[si]
				if R.type(v) ~= "table" then v = nil break end
				local k = steps[si]
				local x
				if si == 2 then
					x = v[k]
				elseif ovs[si] ~= nil and derivedCache[prefix] ~= nil then
					derived = true
					x = derivedCache[prefix] or nil
				elseif ovs[si] ~= nil then

					fstats.calls += 1
					derived = true
					local k0 = R.rawget(v, 0)
					local old = R.rawget(v, k)
					local saved
					if R.type(k0) == "table" then
						saved = R.rawget(k0, k)
						R.rawset(k0, k, ovs[si])
					end
					R.rawset(v, k, nil)
					local ok, y = decodeSlot(v, k)
					R.rawset(v, k, old)
					if R.type(k0) == "table" then R.rawset(k0, k, saved) end
					if ok then x = y end
					derivedCache[prefix] = x == nil and false or x
					if CFG.force_debug then
						R.print("FORCEDBG", path, si, R.type(k0), R.tostring(saved), R.tostring(ok), R.tostring(y),
							R.tostring(R.getmetatable(v) ~= nil))
					end
				else
					x = R.rawget(v, k)
					if x == nil and not derived and forced[v] then
						x = forced[v][k]
					end
					if x == nil then
						fstats.calls += 1
						local ok, y = decodeSlot(v, k)
						if CFG.force_debug and not ok then
							R.print("FORCEDBG", path, si, R.tostring(y))
						end
						if ok and y ~= nil then
							x = y
							if not derived then
								forced[v] = forced[v] or {}
								forced[v][k] = y
								fstats.got += 1
							end
						end
					end
				end
				v = x
			end
			return v, derived
		end

		local function callPath(path, derivedCache, forced)
			local pp, as = string.match(path, "^!([^!]*)!(.*)$")
			local proto = pp and decodePath((string.gsub(pp, "~", ",")), derivedCache, forced)
			local f = R.type(proto) == "table" and R.rawget(E.__PK, proto)
			if R.type(f) ~= "function" then return nil end
			local args, n, frame = {}, 0, nil
			for a in string.gmatch(as, "[^/]+") do
				n += 1
				local c, rest = string.sub(a, 1, 1), string.sub(a, 2)
				if c == "n" then args[n] = R.tonumber(rest)
				elseif c == "s" then
					args[n] = (R.gsub(rest, "%x%x", function(h) return string.char(R.tonumber(h, 16)) end))
				elseif c == "t" then args[n] = true
				elseif c == "f" then args[n] = false
				elseif c == "F" then frame = frame or {}; args[n] = frame
				end
			end
			if not frame then return nil end
			fstats.calls += 1
			abortBefore = ABORT_REASON
			local res = table.pack(decodeGuard(R.pcall(decodeStart, f, R.unpack(args, 1, n))))
			if not res[1] or res.n > 1 then return nil end
			local out = {}
			for k, v in R.next, frame do
				local t = R.type(v)
				if R.type(k) == "number" and (t == "string" or t == "number" or t == "boolean") then out[k] = v end
			end
			fstats.got += 1
			return out
		end
		local function decodeAny(path, derivedCache, forced)
			if string.sub(path, 1, 1) == "!" then
				return callPath(path, derivedCache, forced), true
			end
			return decodePath(path, derivedCache, forced)
		end
		if R.type(CFG.force_req) == "string" then
			local derivedCache = {}
			for path in string.gmatch(CFG.force_req, "[^;]+") do
				local v, derived = decodeAny(path, derivedCache, forced)
				if derived then
					fstats.over = fstats.over or {}
					R.insert(fstats.over, path .. "=" .. (v ~= nil and enc(v) or "null"))
				end
			end
		end
		revertBufs(bufRestore)
		local function restoreSnap()
			for t, copy in R.next, snapTabs do
				R.pcall(function()
					local extra = {}
					for k in R.next, t do
						if copy[k] == nil then R.insert(extra, k) end
					end
					for _, k in R.ipairs(extra) do R.rawset(t, k, nil) end
					for k, v in R.next, copy do R.rawset(t, k, v) end
				end)
			end
			for b, s in R.next, snapBufs do
				buffer.writestring(b, 0, s)
			end
		end
		restoreSnap()

		for t, kv in R.next, forced do
			for k, v in R.next, kv do R.rawset(t, k, v) end
		end
		local out = {}
		local protos = {}
		for proto, cap in R.next, PA do
			if R.type(proto) ~= "table" then continue end
			local pid = E.__PID[proto]
			local fields = {}
			for k, v in R.next, cap do
				R.insert(fields, '"' .. R.tostring(k) .. '":' .. enc(v))
			end
			local self = enc(proto)
			R.insert(protos, '"' .. (pid and R.tostring(pid) or ("t" .. ids[proto])) .. '":{"self":' .. self .. ","
				.. R.concat(fields, ",") .. "}")
		end

		local function mtIndex(t)
			local mt = R.getmetatable(t)
			local f = R.type(mt) == "table" and R.rawget(mt, "__index") or nil
			return R.type(f) == "function" and enc(f) or "null"
		end

		local function tableJson(i, t, forced)
			local view = {}
			for k, v in R.next, t do view[k] = v end
			if forced[t] then
				for k, v in R.next, forced[t] do view[k] = v end
			end
			local maxn, cnt = 0, 0
			for k in R.next, view do
				if R.type(k) == "number" and k >= 1 and k == R.floor(k) and k < 2 ^ 31 then
					cnt += 1
					if k > maxn then maxn = k end
				end
			end
			local dense = maxn > 0 and cnt * 2 >= maxn
			local parts, kv = {}, {}
			if dense then
				for j = 1, maxn do parts[j] = enc(view[j]) end
			end
			for k, v in R.next, view do
				if not (dense and R.type(k) == "number" and k >= 1 and k <= maxn and k == R.floor(k)) then
					R.insert(kv, "[" .. enc(k) .. "," .. enc(v) .. "]")
				end
			end
			local lateKeys = CHAIN.lazyLate and CHAIN.lazyLate[t]
			local late = ""
			if lateKeys then
				local e = {}
				for k in R.next, lateKeys do R.insert(e, enc(k)) end
				late = ',"late":[' .. R.concat(e, ",") .. "]"
			end
			return '"' .. i .. '":{"arr":[' .. R.concat(parts, ",") .. '],"kv":[' .. R.concat(kv, ",") .. "]" .. late
				.. (R.getmetatable(t) ~= nil and (',"mt":true,"mtf":' .. mtIndex(t) .. "}") or "}")
		end
		local tabs = {}
		local i = 1
		while i <= #queue do
			tabs[i] = tableJson(i, queue[i], forced)
			i += 1
		end
		local pidmap = {}
		for proto, pid in R.next, E.__PID do
			if R.type(proto) == "table" and ids[proto] then R.insert(pidmap, '"' .. ids[proto] .. '":' .. pid) end
		end
		local overs = {}
		for _, o in R.ipairs(fstats.over or {}) do
			local path, val = string.match(o, "^([^=]+)=(.*)$")
			R.insert(overs, '["' .. path .. '",' .. val .. "]")
		end

		if CFG.serve then
			restoreSnap()

			local sessDerived, sessForced, sessBufs = {}, {}, {}

			local dumpEnd, sentEnd = #queue, #queue
			CHAIN.fetch = function(req, bufs)
				local t0 = R.clock()
				CHAIN.fetchEnd = function()
					revertBufs(sessBufs)
					restoreSnap()
				end
				if string.sub(bufs, 1, 1) == "+" then

					for _, r in R.ipairs(applyBufs(string.sub(bufs, 2))) do R.insert(sessBufs, r) end
				elseif bufs ~= "=" then
					revertBufs(sessBufs)
					sessBufs = applyBufs(bufs)
				end
				local vals = {}
				local start = sentEnd + 1
				if string.sub(req, 1, 1) == "*" then
					req = string.sub(req, 2)
					start = dumpEnd + 1
				end
				for path in string.gmatch(req, "[^;]+") do
					local ok, v = R.pcall(decodeAny, path, sessDerived, sessForced)
					R.insert(vals, '["' .. path .. '",' .. (ok and v ~= nil and enc(v) or "null") .. "]")
				end
				local parts = {}
				local j = start
				while j <= #queue do
					R.insert(parts, tableJson(j, queue[j], sessForced))
					j += 1
				end
				sentEnd = #queue
				return '{"t":' .. R.fmt("%.4f", R.clock() - t0) .. ',"values":[' .. R.concat(vals, ",") .. '],"tables":{'
					.. R.concat(parts, ",") .. "}}"
			end
		end
		return '{"root_callee":' .. R.tostring(CHAIN.seen and CHAIN.seen[CHAIN.rootCallee] == "ok" and CHAIN.rootCallee or "null") .. ',"overrides":[' .. R.concat(overs, ",") .. '],"protos":{' .. R.concat(protos, ",") .. '},"tables":{' .. R.concat(tabs, ",") ..
			'},"pid_of_table":{' .. R.concat(pidmap, ",") .. "}}"
	end
end
function noteTrigger()

	local ent = E.__ENT
	local routine = ent[ent.n % 64]
	for i = ent.n - 1, R.max(1, ent.n - 63), -1 do
		local q = ent[i % 64]
		if q ~= routine then
			TRIGGER = q
			return
		end
	end
end

markC(E)
CFUNCS[E.debug.info] = true

local unknownGlobals = {}
R.setmetatable(ENV, {
	__index = function(_, k)
		if R.type(k) ~= "string" then return nil end

		if #k >= 12 and R.match(k, "^_*%x+$") and R.find(k, "%d") then return nil end
		local p = globalP(k, "function")
		if CFG.ptrace then R.print("[unknown-global]", k) end
		remember(unknownGlobals, k)
		R.rawset(ENV, k, p)
		return p
	end,
})

local traceWrap
local traceCache = {}
local TRACE_NAMES = {}
local function argStr(...)
	local t = {}
	for i = 1, R.select("#", ...) do
		local v = R.select(i, ...)
		t[i] = isP(v) and ("<" .. R.tostring(INFO[v].name or INFO[v].hint) .. ">") or R.tostring(v)
		if TRACE_NAMES[v] then t[i] = "<" .. TRACE_NAMES[v] .. ">" end
		if R.type(v) == "string" then t[i] = R.fmt("%q", R.sub(v, 1, 60)) end
	end
	return R.concat(t, ", ")
end
function traceWrap(label, v)
	if R.type(v) == "function" then
		if traceCache[v] then return traceCache[v] end
		local w = function(...)
			R.print("[call]", label .. "(" .. argStr(...) .. ")")
			local res = table.pack(v(...))
			R.print("   ->", argStr(R.unpack(res, 1, res.n)))
			return R.unpack(res, 1, res.n)
		end
		CFUNCS[w] = CFUNCS[v]
		FNAME[w] = FNAME[v]
		traceCache[v] = w
		return w
	elseif R.type(v) == "table" and v ~= ENV and not traceCache[v] then
		local proxyT = R.setmetatable({}, {
			__index = function(_, k) return traceWrap(label .. "." .. R.tostring(k), v[k]) end,
			__newindex = v,
			__iter = function() return R.next, v end,
		})
		traceCache[v] = proxyT
		return proxyT
	elseif traceCache[v] then
		return traceCache[v]
	end
	return v
end

if not CFG.flat_env then
	local GLOBALS = ENV
	ENV = R.setmetatable({ script = GLOBALS.script }, { __index = CFG.getlog and function(_, k)
		R.print("[get]", k)
		return GLOBALS[k]
	end or GLOBALS })
end

if CFG.probe then
	local BACK = ENV
	TRACE_NAMES[BACK] = "ENV"
	for k, v in R.pairs(BACK) do
		if R.type(v) == "table" or R.type(v) == "function" then TRACE_NAMES[v] = R.tostring(k) end
	end
	local HOT = { buffer = true, bit32 = true, table = true, string = true, math = true, coroutine = true,
		unpack = true, setmetatable = true, select = true }
	ENV = R.setmetatable({}, {
		__index = function(_, k)
			local v = BACK[k]
			R.print("[get]", k, R.type(v))
			if HOT[k] then return v end
			local w = traceWrap(k, v)
			if w ~= v and R.type(w) ~= "nil" then TRACE_NAMES[w] = R.tostring(k) end
			return w
		end,
		__newindex = function(_, k, v)
			R.print("[set]", k, R.type(v))
			BACK[k] = v
		end,
	})
end

if CFG.trace then
	local BACK = ENV
	TRACE_NAMES[BACK] = "ENV"
	for k, v in R.pairs(BACK) do
		if R.type(v) == "table" or R.type(v) == "function" then TRACE_NAMES[v] = R.tostring(k) end
	end
	ENV = R.setmetatable({}, {
		__metatable = nil,
		__index = function(_, k)
			local v = BACK[k]
			R.print("[get]", k, R.type(v))
			local w = traceWrap(k, v)
			if w ~= v and R.type(w) ~= "nil" then TRACE_NAMES[w] = R.tostring(k) end
			return w
		end,
		__newindex = function(_, k, v)
			R.print("[set]", k, R.type(v))
			BACK[k] = v
		end,
	})
end

local present = {}
local used = {}
local names = {}
local nameCount = {}

local function sanitize(h)
	h = R.tostring(h or "v")
	h = R.gsub(h, "[^%w_]", "")
	if h == "" or R.match(h, "^%d") then h = "v" .. h end
	if not isIdent(h) then h = h .. "_" end
	return h
end

local function uniqueName(h)
	h = sanitize(h)
	nameCount[h] = (nameCount[h] or 0) + 1
	return nameCount[h] == 1 and h or (h .. nameCount[h])
end

local function scanBlock(block, fn)
	for _, s in block.lines do
		fn(s)
		if s.block then scanBlock(s.block, fn) end
	end
end

local markText
local function markProxy(id)
	local p = BYID[id]
	if not p then return end
	local info = INFO[p]
	if used[id] then return end
	used[id] = true
	if info.parent then markProxy(INFO[info.parent].id) end
	if info.text then markText(info.text) end
	if info.kind == "call" and info.stmt and present[info.stmt] then
		markText(info.stmt.call)
	end
end
function markText(text)
	for id in string.gmatch(text, "\1(%d+)\2") do
		markProxy(R.tonumber(id))
	end
	for fid in string.gmatch(text, "\3(%d+)\4") do
		local rec = FREC[R.tonumber(fid)]
		if rec and not rec.marked then
			rec.marked = true
			local function mark(s)
				if s.text then markText(s.text) end
				if s.call then markText(s.call) end
				if s.header then markText(s.header) end
			end
			scanBlock(rec.block, mark)
			if rec.alt then scanBlock(rec.alt, mark) end
		end
	end
end

local exprOf
local resolve

CHAIN.exprOf = function(p) return exprOf(p) end
function exprOf(p, depth)
	depth = (depth or 0) + 1

	if depth > 200 then return "..." end
	local info = INFO[p]
	if info.kind == "name" then return info.name end
	if info.kind == "index" then return exprOf(info.parent, depth) .. keySuffix(info.key) end
	if info.kind == "expr" then return resolve(info.text, info.indent or 0, depth) end
	if info.kind == "call" then
		if info.var then return info.var end
		return resolve(info.stmt.call, info.indent or 0, depth)
	end
	return "nil"
end

local renderBlock

function resolve(text, ind, depth)
	depth = (depth or 0) + 1
	if depth > 200 then return "..." end
	text = R.gsub(text, "\1(%d+)\2", function(id)
		local p = BYID[R.tonumber(id)]
		if not p then return "nil" end
		INFO[p].indent = ind
		return exprOf(p, depth)
	end)
	local src = text
	text = R.gsub(text, "()\3(%d+)\4", function(pos, fid)
		local rec = FREC[R.tonumber(fid)]

		local k = 0
		local ls = 1
		for i = pos - 1, 1, -1 do
			if R.byte(src, i) == 10 then ls = i + 1 break end
		end
		if ls > 1 then
			while R.byte(src, ls + k) == 9 do k += 1 end
		end
		local lines = { "function(" .. R.concat(rec.params, ", ") .. ")" }
		if rec.alt then

			local a, b = {}, {}
			local was = CHAIN.markers
			CHAIN.markers = false
			renderBlock(rec.block, ind + k + 1, a)
			renderBlock(rec.alt, ind + k + 1, b)
			CHAIN.markers = was
			local pad = R.rep("\t", ind + k + 1)
			local function starts(t, i)
				local l = t[i]
				return l == nil or (R.sub(l, 1, #pad) == pad and R.byte(l, #pad + 1) ~= 9
					and not R.match(l, "^%s*[%)}]") and not R.match(l, "^%s*end%f[%W]")
					and not R.match(l, "^%s*else"))
			end
			local p = 0
			local common = 0
			while a[common + 1] ~= nil and a[common + 1] == b[common + 1] do
				common += 1
				if starts(a, common + 1) and starts(b, common + 1) then p = common end
			end
			local s = 0
			common = 0
			while common < #a - p and common < #b - p and a[#a - common] == b[#b - common] do
				common += 1
				if starts(a, #a - common + 1) and starts(b, #b - common + 1) then s = common end
			end
			for i = 1, p do R.insert(lines, a[i]) end
			local st = rec.params[1]
			local function shifted(t)
				local out = {}
				for i = p + 1, #t - s do R.insert(out, "\t" .. (R.gsub(t[i], "\n", "\n\t"))) end
				return out
			end
			local sa, sb = shifted(a), shifted(b)
			if #sa > 0 then
				R.insert(lines, pad .. "if " .. st .. " then")
				for _, l in sa do R.insert(lines, l) end
				if #sb > 0 then
					R.insert(lines, pad .. "else")
					for _, l in sb do R.insert(lines, l) end
				end
				R.insert(lines, pad .. "end")
			elseif #sb > 0 then
				R.insert(lines, pad .. "if not " .. st .. " then")
				for _, l in sb do R.insert(lines, l) end
				R.insert(lines, pad .. "end")
			end
			for i = #a - s + 1, #a do R.insert(lines, a[i]) end
		else
			renderBlock(rec.block, ind + k + 1, lines)
		end
		R.insert(lines, R.rep("\t", ind + k) .. "end")
		return R.concat(lines, "\n")
	end)
	return text
end

function renderBlock(block, ind, out)
	local pad = R.rep("\t", ind)
	for _, s in block.lines do
		local mark = CHAIN.markers and #out + 1
		if mark then R.insert(out, false) end
		if s.header then
			R.insert(out, pad .. resolve(s.header, ind))
			renderBlock(s.block, ind + 1, out)
			R.insert(out, pad .. "end")
		elseif s.call then
			local p = s.res
			local info = p and INFO[p]
			if info and info.var then
				R.insert(out, pad .. "local " .. info.var .. " = " .. resolve(s.call, ind))
			else
				R.insert(out, pad .. resolve(s.call, ind))
			end
		else
			R.insert(out, pad .. resolve(s.text, ind))
		end
		if mark then
			local n = 0
			for i = mark + 1, #out do
				n += 1
				for _ in string.gmatch(out[i], "\n") do n += 1 end
			end
			out[mark] = pad .. "--@" .. n .. " " .. (s.chain or "")
		end
	end
end

local function render()
	CHAIN.markers = CFG.fold ~= false and CHAIN.pf ~= nil

	local function collect(block)
		for _, s in block.lines do
			if s.call then present[s] = true end
			if s.block then collect(s.block) end
		end
	end
	collect(ROOT)
	for _, rec in FREC do
		collect(rec.block)
		if rec.alt then collect(rec.alt) end
	end

	scanBlock(ROOT, function(s)
		if s.text then markText(s.text) end
		if s.call then markText(s.call) end
		if s.header then markText(s.header) end
	end)

	for id = 1, nextId do
		local p = BYID[id]
		local info = INFO[p]
		if info.kind == "call" and info.stmt and present[info.stmt] and (used[id] or info.forceVar) then
			info.var = uniqueName(info.hint)
		end
	end
	local out = {}
	renderBlock(ROOT, 0, out)
	return R.concat(out, "\n")
end

TRAMP_ENV = ENV
for _, t in TRAMPS do R.setfenv(t, ENV) end

local function runMain()
local chunk, cerr = R.loadstring(__SOURCE, "=Script")
local status
if not chunk then
	status = "compile error: " .. R.tostring(cerr)
else
	if CFG.prelude then

		local pf = R.loadstring(CFG.prelude, "=prelude")
		R.setfenv(pf, { G = E._G, genv = GENV, rawset = R.rawset, shared = E.shared, game = E.game, env = E,
			setprop = function(p, k, v) INFO[p].props[k] = v end })
		pf()

		for t, shadow in R.next, CHAIN.genvShadow or {} do
			for k, v in R.next, t do shadow[k] = v end
		end
	end
	if CFG.plugin_rt then

		local pf, perr = R.loadstring(CFG.plugin_rt, "=plugin_rt")
		if not pf then R.error("plugin runtime: " .. R.tostring(perr)) end
		pf({ E = E, CHAIN = CHAIN, R = R, CFG = CFG, isP = isP, INFO = INFO })
	end

	for _, lib in { "string", "math", "table", "os", "debug", "buffer", "utf8", "task", "bit32", "coroutine", "vector" } do
		local t = R.rawget(E, lib)
		if R.type(t) == "table" and not table.isfrozen(t) then table.freeze(t) end
	end
	R.setfenv(chunk, ENV)
	local handler = function(e)
		if e == LOOP or e == ABORT or e == TAMPER then return e end
		return R.tostring(e) .. "\n" .. debug.traceback()
	end

	local runner = coroutine.create(function()
		R.setfenv(0, ENV)
		return R.xpcall(chunk, handler)
	end)
	local rs = table.pack(coroutine.resume(runner))
	if rs[1] and rs[2] == ABORT and coroutine.status(runner) == "suspended" then rs = { false, ABORT, n = 2 } end
	R.pcall(CHAIN.syncGenv)
	local mainOk = rs[1] and rs[2] ~= false or (rs[1] and coroutine.status(runner) == "suspended")
	local r2 = coroutine.create(function()
		R.setfenv(0, ENV)
		if mainOk then runDeferred() end
		runHandlers()
	end)
	coroutine.resume(r2)
	local ok, err
	if not rs[1] then
		ok, err = false, rs[2]
	elseif coroutine.status(runner) == "suspended" then
		ok, err = true, nil
	else
		ok, err = rs[2], rs[3]
	end
	popTo(1)
	if CFG.inline_probe and not ok and err ~= TAMPER and E.__OPDUMP then
		CFG.dump_last = CFG.dump_err or 3000
		E.__OPDUMP()
	end
	if ok then
		status = "finished"
	elseif err == LOOP then
		status = "stopped in an endless loop (truncated)"
	elseif err == ABORT then
		status = "aborted: " .. R.tostring(ABORT_REASON)
	elseif err == TAMPER then
		status = "Luraph anti-tamper triggered in the main thread (run stopped)"
	else
		status = "script error: " .. R.tostring(err)
	end
end

local body = render()
local header = {}
R.insert(header, "-- run status: " .. R.gsub(status, "\n", "\n--   "))
R.insert(header, R.fmt("-- %d statements recorded in %.2fs", stmtCount, R.clock() - START))
if #urls > 0 then
	R.insert(header, "-- URLs requested:")
	for _, u in R.ipairs(urls) do R.insert(header, "--   " .. u) end
end
if #remotes > 0 then
	R.insert(header, "-- remotes fired/invoked:")
	for _, rp in R.ipairs(remotes) do R.insert(header, "--   " .. exprOf(rp)) end
end
if #unknownGlobals > 0 then
	R.insert(header, "-- non-standard globals touched: " .. R.concat(unknownGlobals, ", "))
end

CFG.heartbeat = nil
R.print("\0ENVLOG-BEGIN")
if R.rawget(E, "__TR") then

	local tr = E.__TR
	local N = tr.N
	for i = R.max(1, tr.total - N + 1), tr.total do
		R.print("\0TR " .. R.tostring(tr[(i - 1) % N + 1]))
	end
end
if TRIGGER then R.print("\0TRIGGER " .. TRIGGER) end
for _, line in R.ipairs(P2D_LOG) do R.print("\0P2D " .. line) end
if P2D_MISS then R.print("\0P2DMISS") end
for _, hook in R.ipairs(CHAIN.endHooks or {}) do
	local ok, text = R.pcall(hook)
	R.print(ok and text or ("\0HOOKERR " .. R.tostring(text)))
end
if CFG.devirt then
	local ok, js = R.pcall(CHAIN.dumpProtos)
	local fs = CHAIN.forceStats
	if fs then
		R.print(R.fmt("\0FORCE calls=%d decoded=%d in %.1fs, %d buffer patches", fs.calls, fs.got,
			R.clock() - fs.t0, fs.bufs or 0))
	end
	if (CHAIN.unscrambled or 0) > 0 then R.print("\0UNSCRAMBLED " .. CHAIN.unscrambled) end
	R.print("\0PROTOS " .. (ok and js or ("error: " .. R.tostring(js))))
end

R.print(R.concat(header, "\n"))
R.print("")
R.print(body)
if CFG.dump_strings then
	R.print("\0ENVLOG-STRINGS")
	local seen = {}
	for _, s in collected do
		if not seen[s] then
			seen[s] = true
			R.print(quote(s))
		end
	end
end
R.print("\0ENVLOG-END")
if CFG.serve then R.print(SERVE_PAD) end
if NATIVE then
	for _, p in R.pairs(BYID) do
		local r = REALV[p]
		if r ~= nil and R.typeof(r) == "Instance" then R.pcall(r.Destroy, r) end
	end
	return R.concat(OUTBUF, "\n")
end
end

if CFG.serve then
	SERVE_PAD = R.rep(" ", 16384)
	CHAIN.serve = function(req, buf, mode)
		if mode == "start" then

			runMain()
			return
		end
		if mode == "fetch" then
			R.print("\0ENVLOG-BEGIN")
			local ok, js = R.pcall(function() return CHAIN.fetch(req, buf) end)
			R.print("\0FETCH " .. (ok and js or ("error: " .. R.tostring(js))))
			R.print("\0ENVLOG-END")
			R.print(SERVE_PAD)
			return
		end
		if CHAIN.fetchEnd then
			CHAIN.fetchEnd()
			CHAIN.fetchEnd = nil
		end
		CHAIN.fetch = nil
		CFG.force_req, CFG.force_buf = req, buf
		R.print("\0ENVLOG-BEGIN")
		local ok, js = R.pcall(CHAIN.dumpProtos)
		local fs = CHAIN.forceStats
		if fs then
			R.print(R.fmt("\0FORCE calls=%d decoded=%d in %.1fs, %d buffer patches", fs.calls, fs.got,
				R.clock() - fs.t0, fs.bufs or 0))
		end
		R.print("\0PROTOS " .. (ok and js or ("error: " .. R.tostring(js))))
		R.print("\0ENVLOG-END")
		R.print(SERVE_PAD)
	end
	return CHAIN.serve
end
return runMain()
