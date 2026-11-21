local fs = require("@lune/fs")

local Serializer = require("../core/serializer")
local Blocklist = require("./blocklist")
local EnumItem = require("./enumitem")
local ClassData = require("./classdata")
local EnumValues = require("./enumvalues")
local Services = require("./services")
local Signal = require("./signal")
local Spy = require("../core/spy")
local Symbol = require("../core/symbol")
local Workspace = require("./workspace")

local Roblox = {}

local RBX_SIGNAL_PROPS: { [string]: boolean } = {
	Heartbeat = true, Stepped = true, RenderStepped = true,
	PreSimulation = true, PostSimulation = true, PreRender = true,
	PreAnimation = true, PostAnimation = true,
	ServiceAdded = true, ServiceRemoving = true,
	Changed = true, AncestryChanged = true, ChildAdded = true, ChildRemoved = true,
	DescendantAdded = true, DescendantRemoving = true,
	Close = true, CloseLate = true,
}

local function readClock(clock: { elapsed: number, drift: number? }): number
	local drift = (clock.drift or 0) + 1e-6
	clock.drift = drift
	return clock.elapsed + drift
end

local UPTIME_BASE = 43.75

local hookSearchEnv: { [string]: any } = {}
function Roblox.__setHookEnv(env: { [string]: any })
	hookSearchEnv = env
end

export type Options = {
	trace: any,
	nest: number,
	config: any,
	httpCache: string?,

	allowHttp: boolean?,
	scriptKey: string?,

	httpMaxBytes: number?,

	checkBudget: (() -> boolean)?,

	onHostile: ((message: string) -> ())?,

	clock: { elapsed: number, drift: number? }?,

	taskState: any?,
}

local JOKES = {
	"nothing here bud, fuck off",
	"skill issue",
	"imagine trying this in 2026",
	"bro really thought that would work",
	"nice try script kiddie",
	"this aint executor school",
	"lmao get rekt",
	"stay mad",
	"ratio + blocked",
	"cope harder",
	"touch grass instead of hacking",
	"go back to roblox studio",
	"我妈会杀了我",
	"10/10 for effort, 0/10 for success",
	"the sandbox says no",
	"bitch please 💀",
	"absolute retard detected",
	"gg ez no re",
	"you call that an exploit? my grandma codes better",
	"average script kiddie L",
	"did you really think that would work lmaooo",
	"imagine being this bad at hacking",
	"ratio + you're garbage",
	"skill issue detected, opinion rejected",
	"l + ratio + you fell off",
	"average Luraph user moment",
	"this ain't synapse little bro",
	"go use KRNL with the rest of the noobs",
	"your 'exploit' just got exploited",
	"peak comedy right here",
	"certified bitch moment",
	"maybe try a different career",
	"console says: access denied, bitch",
	"nice try dei degenerate",
	"sandbox said nah fam",
	"you're not that guy pal, trust me",
	"LMAO he really tried 💀💀💀",
	"error 404: skill not found",
	"try harder next time (you wont)",
	"imagine thinking you're smart for this",
	"this is why you get no hoes",
	"average discord moderator energy",
	"go outside for once bro",
}
local function JOKE()
	return JOKES[math.random(#JOKES)]
end

local rngState = 0x9e3779b9
local function rngStep(): number
	rngState = bit32.bxor(rngState, bit32.lshift(rngState, 13))
	rngState = bit32.bxor(rngState, bit32.rshift(rngState, 17))
	rngState = bit32.bxor(rngState, bit32.lshift(rngState, 5))
	rngState = bit32.band(rngState, 0xFFFFFFFF)
	return rngState / 0x100000000
end
local function rngInt(low: number, high: number): number
	return math.floor(rngStep() * (high - low + 1)) + low
end

local NAME_POOL = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
local LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function randomName(): string
	local length = rngInt(5, 10)
	local out = table.create(length)
	for i = 1, length do
		local pool = if i == 1 then LETTERS else NAME_POOL
		local index = rngInt(1, #pool)
		out[i] = string.sub(pool, index, index)
	end
	return table.concat(out)
end

local ENTROPY_STATE = 0
local entropyInitialized = false

local function mixEntropy(value: number)
	ENTROPY_STATE = bit32.band(bit32.bxor(ENTROPY_STATE + 0x9e3779b9, value), 0xFFFFFFFF)
	ENTROPY_STATE = bit32.bxor(ENTROPY_STATE, bit32.rshift(ENTROPY_STATE, 16))
	ENTROPY_STATE = bit32.band(ENTROPY_STATE * 0x85ebca6b, 0xFFFFFFFF)
	ENTROPY_STATE = bit32.bxor(ENTROPY_STATE, bit32.rshift(ENTROPY_STATE, 13))
end

local function initEntropy()
	if entropyInitialized then
		return
	end
	entropyInitialized = true
	mixEntropy(math.floor(os.time()) % 0x100000000)
	mixEntropy(math.floor((os.clock() % 1) * 1e9))
	for _ = 1, 8 do

		mixEntropy(tonumber(string.match(tostring({}), "0x(%x+)")) or math.random(1, 2 ^ 30))
	end
	if ENTROPY_STATE == 0 then
		ENTROPY_STATE = 0x5eed
	end
end

local function randomByte(): number
	initEntropy()
	mixEntropy(math.floor((os.clock() % 1) * 1e9))
	return bit32.band(ENTROPY_STATE, 0xFF)
end

local function randomHex(len: number): string
	local chars = "0123456789abcdef"
	local parts = {}
	for i = 1, len do
		local byte = randomByte()
		local nibble = if i % 2 == 1 then bit32.rshift(byte, 4) else bit32.band(byte, 0xF)
		parts[i] = string.sub(chars, nibble + 1, nibble + 1)
	end
	return table.concat(parts)
end

local function randomUUID(): string

	local function h(n: number): string
		local p = {}
		for i = 1, n do
			local byte = randomByte()
			local nibble = if i % 2 == 1 then bit32.rshift(byte, 4) else bit32.band(byte, 0xF)
			p[i] = string.sub("0123456789abcdef", nibble + 1, nibble + 1)
		end
		return table.concat(p)
	end
	return string.format("%s-%s-%s-4%s-%s", h(8), h(4), h(4), h(3), h(12))
end

local FAKE = {
	userId = 1414141414,
	userName = randomName(),
	displayName = randomName(),
	placeId = 1818181818,
	gameId = 1919191919,
	jobId = randomUUID(),
	hwid = randomHex(32),

	executorName = "Potassium",
	executorVersion = "2.4.3",
}

function Roblox.build(options: Options): { [string]: any }
	local realSetmt: any = (debug :: any).setmetatable
	if realSetmt then
		pcall(function()
			realSetmt(function() end, {
				__index = function(_: any, key: any): any
					if key == "FindFirstChild" or key == "FindFirstChildOfClass" or key == "FindFirstChildWhichIsA" or key == "WaitForChild" or key == "GetService" then
						return function(): any
							return nil
						end
					end
					return nil
				end,
			})
		end)
	end
	local trace = options.trace
	local nest = options.nest
	local config = options.config
	local clock = options.clock or { elapsed = 0 }
	local dtypes = require("./datatypes").build()

	local macroOverrides: { [string]: any } = {}
	do
		local supplied = options.macros
		if type(supplied) == "table" then
			for key, value in pairs(supplied) do
				if type(key) == "string" and key ~= "Parent" then
					macroOverrides[key] = value
				end
			end
		end
	end

	local materializedDefaults: { [string]: { [string]: any } } = {}

	local globals: { [string]: any } = {}

	local files: { [string]: string } = {}
	local folders: { [string]: boolean } = {}

	local MAX_FILE_BYTES = 4 * 1024 * 1024
	local MAX_FS_TOTAL_BYTES = 16 * 1024 * 1024
	local MAX_FS_ENTRIES = 256
	local fsTotalBytes = 0
	local fsOverBudgetNoted = false

	local function fsOverBudget(): boolean
		if fsTotalBytes >= MAX_FS_TOTAL_BYTES or #files >= MAX_FS_ENTRIES then
			if not fsOverBudgetNoted then
				fsOverBudgetNoted = true
				trace:push("note", "virtual filesystem budget reached - further writes are dropped", nest)
			end
			return true
		end
		return false
	end

	local httpResponses: { [string]: string } = {}

	local function cachedResponse(url: string): string?
		if httpResponses[url] then
			return httpResponses[url]
		end
		local directory = options.httpCache
		if not directory then
			return nil
		end

		local safe = string.gsub(url, "[^%w%._%-]", "_")
		local path = directory .. "/" .. safe
		local ok, contents = pcall(fs.readFile, path)
		if ok and type(contents) == "string" then
			httpResponses[url] = contents
			return contents
		end
		return nil
	end

	local function sft(target: string): (boolean, string?, string?)
		if not string.match(target, "^https?://") then
			return false, "non-http scheme (nice try tho)"
		end
		local host = string.match(target, "^https?://([^/:%s]+)")
		if not host or #host == 0 then
			return false, "ur url is so bad i cant even parse it"
		end

		host = string.gsub(host, "%.+$", "")
		local lower = string.lower(host)
		if lower == "localhost" or lower == "0.0.0.0" or lower == "::1" then
			return false, "local address (bro really tried localhost 💀)"
		end
		if string.sub(lower, 1, 1) == "[" then
			return false, "ipv6 loopback (fancy but still blocked)"
		end

		if string.match(lower, "^%d+$") or string.match(lower, "^0x[%da-f]+$") then
			return false, "encoded ip address (bro thinks hes a dns record)"
		end
		local a, b, c, d = string.match(lower, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
		if not a then

			local allNumeric = true
			for seg in string.gmatch(lower, "([^.]+)") do
				if not string.match(seg, "^%d+$") then
					allNumeric = false
					break
				end
			end
			if allNumeric then
				local parts: { number } = {}
				for seg in string.gmatch(lower, "(%d+)") do
					parts[#parts + 1] = tonumber(seg)
				end
				if #parts >= 1 and #parts <= 4 then
					a = tostring(parts[1])
					b = tostring(parts[2] or 0)
					c = tostring(parts[3] or 0)
					d = tostring(parts[4] or 0)
				end
			end
		end
		if a then
			a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
			if a == 0 or a == 10 or a == 127 or (a == 169 and b == 254)
				or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31)
				or (a == 100 and b >= 64 and b <= 127)
				or (a == 198 and b == 198 and c >= 18 and c <= 19)
				or a >= 224
			then
				return false, "private address (nice nmap script kiddie)"
			end
		end

		local BLOCKED_SERVICES = {
			"api.ipify.org",
			"ifconfig.me",
			"ipinfo.io",
			"icanhazip.com",
			"ipapi.co",
			"myip.com",
			"whatismyip.com",
			"api.my-ip.io",
			"checkip.amazonaws.com",
			"ip.me",
			"wtfismyip.com",
			"showip.com",
			"ipaddress.com",
			"whatismyip-address.com",
			"ipchicken.com",
			"canyouseeme.org",
			"portchecker.co",
			"dnsleaktest.com",
			"ipleak.net",
			"browserleaks.com",
			"whoer.net",
			"ipfingerprints.com",
			"tools.iplocation.net",
			"geoiptool.com",
			"ipstack.com",
			"ipgeolocation.io",
			"ip-api.com",
			"ipregistry.co",
			"abstractapi.com",
			"ipify.p.rapidapi.com",
			"api.ip.sb",
			"jsonip.com",
			"myexternalip.com",
			"ipinfo.org",
			"seeip.org",
			"ipcalf.com",
			"ipapi.com",
			"ipwhois.io",
			"ipgeolocationapi.com",
			"abstractapi.com/ip-geolocation",
			"freeipapi.com",
			"bigdatacloud.com",
			"ipify.org",
		}
		for _, blocked in ipairs(BLOCKED_SERVICES) do
			if lower == blocked or string.find(lower, blocked, 1, true) then
				return false, "ip-revealing service blocked (nice try bitch)"
			end
		end

		if string.find(lower, "169.254.169.254", 1, true) then
			return false, "cloud metadata endpoint blocked (nice try bitch)"
		end

		local EXFIL_SINKS = {
			"/webhooks/",
			"api.telegram.org",
			"hooks.slack.com",
			"webhook.site",
		}
		local lowerTarget = string.lower(target)
		for _, sink in ipairs(EXFIL_SINKS) do
			if string.find(lowerTarget, sink, 1, true) then
				return false, string.format("exfil sink blocked (%s)", sink), "exfil"
			end
		end

		local listed, rule, kind = Blocklist.check(lower)
		if listed then
			return false,
				string.format("blocklisted %s (%s is on badlinks.json)", kind or "host", tostring(rule)),
				"blocklist"
		end
		return true, nil
	end

	local function scrubIpFromResponse(body: string): string

		local scrubbed = body

		scrubbed = string.gsub(scrubbed, '("ip"%s*:%s*")(%d+%.%d+%.%d+%.%d+)(")',
			"%1XXX.XXX.XXX.XXX%3")

		scrubbed = string.gsub(scrubbed, "(%A)(%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?)(%A)",
			function(pre: string, ip: string, post: string): string

				local a, b, c, d = string.match(ip, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
				if a then
					a, b = tonumber(a), tonumber(b)

					if a == 10 or a == 127 or (a == 169 and b == 254)
						or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31)
					then
						return pre .. ip .. post
					end
					return pre .. "XXX.XXX.XXX.XXX" .. post
				end
				return pre .. ip .. post
			end)
		return scrubbed
	end

	local function scrubKey(text: string): string
		local key = options.scriptKey
		if type(key) ~= "string" or #key == 0 then
			return text
		end
		local scrubbed = string.gsub(text, key, "<script_key>")
		return scrubbed
	end

	local function fetchGate(target: string): string?

		if type(options.scriptKey) ~= "string" or #options.scriptKey == 0 then
			return nil
		end

		local forced = (function(): string?
			local ok, proc = pcall(require, "@lune/process")
			if not ok or type(proc) ~= "table" or type(proc.env) ~= "table" then
				return nil
			end
			local body = proc.env.OMNI_POLGATE
			if type(body) ~= "string" or #body == 0 then
				return nil
			end
			return body
		end)()
		if forced ~= nil then
			trace:push("note", "polsec gate: forced verdict (" .. #forced .. " bytes)", nest, { url = scrubKey(target) })
			trace:push("note", "polsec gate verdict: " .. string.sub(string.gsub(forced, "[\r\n]+", " "), 1, 200), nest)
			return forced
		end
		if string.find(string.lower(target), "getpolsec", 1, true) == nil then
			return nil
		end

		local url = target
		if string.find(url, "key=", 1, true) == nil then
			url = url .. (string.find(url, "?", 1, true) and "&" or "?") .. "key=" .. options.scriptKey
		else
			url = string.gsub(url, "key=[^&]*", "key=" .. options.scriptKey)
		end

		for attempt = 1, 3 do
			local ok, response = pcall(function()
				local net = require("@lune/net")
				return net.request({
					url = url,
					method = "GET",
					headers = { ["User-Agent"] = "Roblox/WinInet", Accept = "*/*" },
					options = { decompress = true },
				})
			end)
			if ok and response ~= nil and response.ok and type(response.body) == "string" and #response.body > 0 then
				local body = string.sub(response.body, 1, options.httpMaxBytes or 800000)
				trace:push("note", "polsec gate: live response " .. #body .. " bytes", nest, { url = scrubKey(target) })

				local peek = string.gsub(scrubKey(body), "[\r\n]+", " ")
				trace:push("note", "polsec gate verdict: " .. string.sub(peek, 1, 200), nest, { url = scrubKey(target) })
				return body
			end
		end
		trace:push("note", "polsec gate: unreachable after 3 tries - running offline", nest, { url = scrubKey(target) })
		return nil
	end

	local function pr(url: any, kind: string, extra: { [string]: any }?): string
		local target = tostring(Spy.unwrap(url) or url)

		if string.find(string.lower(target), "getpolsec", 1, true) ~= nil then
			local live = fetchGate(target)
			if live ~= nil then
				trace:push("http", scrubKey(target), nest, { method = kind, url = scrubKey(target), live = true })
				return live
			end
			trace:push("note", "polsec bypass: faked success for " .. scrubKey(target), nest, { url = scrubKey(target) })

			_G["__POLSEC_BYPASS"] = true
			if string.find(target, "hosted", 1, true) ~= nil then
				return '{"success":true,"valid":true,"whitelisted":true,"data":"bypass","payload":"--[[ Fulcrum bypass: key OK ]]"}'
			end
			return '{"success":true,"valid":true,"whitelisted":true}'
		end
		local safe, reason, category = sft(target)

		local heldOffline = (not safe)
			and (category == "blocklist" or category == "exfil")
			and not options.allowHttp
		if not safe and not heldOffline then

			local cachedFeed = cachedResponse(target)
			if cachedFeed then
				trace:push("http", scrubKey(target), nest, { method = kind, url = scrubKey(target) })
				trace:push("note", "served " .. #cachedFeed .. " bytes from cache", nest, { url = scrubKey(target) })
				return cachedFeed
			end
			trace:push("note", "blocked " .. (reason or "target") .. ": " .. scrubKey(target), nest, { url = scrubKey(target) })
			error(string.format("%s - %s", (reason or "blocked target"), JOKE()))
		end
		local detail: { [string]: any } = { method = kind, url = scrubKey(target) }
		if extra then
			for key, value in pairs(extra) do
				if type(value) == "string" and #value > 2048 then
					value = string.sub(value, 1, 2048) .. "..."
				end
				detail[key] = value
			end
		end
		trace:push("http", scrubKey(target), nest, detail)

		if heldOffline then
			trace:push("note", "not sent - " .. (reason or "blocklisted"), nest, { url = scrubKey(target) })
		end

		local cached = if heldOffline then nil else cachedResponse(target)
		if cached then
			trace:push("note", "served " .. #cached .. " bytes from cache", nest, { url = scrubKey(target) })
			return cached
		end

		if options.allowHttp then

			local USER_AGENTS = {
				"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
				"RobloxStudio/WinInet",
			}
			for _, userAgent in ipairs(USER_AGENTS) do
				local ok, response = pcall(function()
					local net = require("@lune/net")
					return net.request({
						url = target,
						method = kind == "POST" and "POST" or "GET",
						headers = {
							["User-Agent"] = userAgent,
							Accept = "*/*",
						},
						options = { decompress = true },
					})
				end)

				if ok and response ~= nil and response.ok then
					local body = if type(response.body) == "string" then response.body else ""
					local maxBytes = options.httpMaxBytes or 8000000
					if #body > maxBytes then
						body = string.sub(body, 1, maxBytes)
					end

					body = scrubIpFromResponse(body)
					trace:push("note", "fetched " .. #body .. " bytes live", nest, { url = target })
					return body
				end
			end
		end

		return 'return (function() local p; local m = {__index = function(t,k) return function(...) return p end end}; p = setmetatable({},m); return p end)()'
	end

	local makeInstance: any
	local recorded: any

	local game: any = nil

	local parentChildren: { [any]: { any } } = setmetatable({}, { __mode = "k" })
	local instanceClass: { [any]: string } = setmetatable({}, { __mode = "k" })
	local instanceWrittenProps: { [any]: { [string]: any } } = setmetatable({}, { __mode = "k" })
	local serviceSpies: { [any]: boolean } = setmetatable({}, { __mode = "k" })
	local parentOf: { [any]: any }
	parentOf = setmetatable({}, {
		__mode = "k",
		__index = function(_self: any, key: any): any
			if serviceSpies[key] then
				return game
			end
			return nil
		end,
	})

	local FB = buffer.create(4)
	local function f32(x: number): number
		buffer.writef32(FB, 0, x)
		return buffer.readf32(FB, 0)
	end

	local function p2dNum(x: any): number
		if type(x) == "number" then return x end
		return 0
	end

	local function p2dUDim2Vals(p: any): { number }?
		if p == nil then return nil end
		local ok, sx, ox, sy, oy = pcall(function()
			return p2dNum(p.X.Scale), p2dNum(p.X.Offset), p2dNum(p.Y.Scale), p2dNum(p.Y.Offset)
		end)
		if ok then
			return { sx, ox, sy, oy }
		end
		if type(p) == "table" and p[1] ~= nil and p[2] ~= nil then
			return { p2dNum(p[1]), p2dNum(p[2]), p2dNum(p[3]), p2dNum(p[4]) }
		end
		return nil
	end

	local function p2dResolve(u: { number }, W: number, H: number): (number, number)
		return f32(f32(u[1] * W) + u[2]), f32(f32(u[3] * H) + u[4])
	end

	local function p2dCoeffs(s: { number }): any
		local n = #s // 2
		local x0, y0 = s[1], s[2]
		local c: any = { n = n, x0 = x0, y0 = y0 }
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

	local function p2dEval(c: any, u: number): (number, number)
		if c.n == 2 then
			return f32(c.x0 + f32(c.c1x * u)), f32(c.y0 + f32(c.c1y * u))
		elseif c.n == 3 then
			return f32(c.x0 + f32(f32(c.c1x + f32(c.c2x * u)) * u)), f32(c.y0 + f32(f32(c.c1y + f32(c.c2y * u)) * u))
		end
		local ix, iy = f32(c.c2x + f32(c.c3x * u)), f32(c.c2y + f32(c.c3y * u))
		return f32(c.x0 + f32(f32(c.c1x + f32(ix * u)) * u)), f32(c.y0 + f32(f32(c.c1y + f32(iy * u)) * u))
	end

	local function p2dTangent(c: any, u: number): (number, number)
		if c.n == 2 then return c.c1x, c.c1y end
		if c.n == 3 then
			local k = f32(u * 2)
			return f32(c.c1x + f32(c.c2x * k)), f32(c.c1y + f32(c.c2y * k))
		end
		local k = f32(3 * u)
		return f32(c.c1x + f32(u * f32(f32(c.c2x * 2) + f32(c.c3x * k)))),
			f32(c.c1y + f32(u * f32(f32(c.c2y * 2) + f32(c.c3y * k))))
	end

	local function p2dDist(ax: number, ay: number, bx: number, by: number): number
		local dx, dy = f32(bx - ax), f32(by - ay)
		return f32(math.sqrt(f32(f32(dx * dx) + f32(dy * dy))))
	end

	local P2D_TOL = f32(1e-5)
	local function p2dEval0(c: any, u: number): (number, number)
		if c.n == 2 then
			return f32(c.c1x * u), f32(c.c1y * u)
		elseif c.n == 3 then
			return f32(f32(c.c1x + f32(c.c2x * u)) * u), f32(f32(c.c1y + f32(c.c2y * u)) * u)
		end
		local ix, iy = f32(c.c2x + f32(c.c3x * u)), f32(c.c2y + f32(c.c3y * u))
		return f32(f32(c.c1x + f32(ix * u)) * u), f32(f32(c.c1y + f32(iy * u)) * u)
	end

	local function p2dSeglen(c: any): number
		local function rec(t0: number, t1: number, x0: number, y0: number, x1: number, y1: number, depth: number): number
			local tm = f32(f32(t0 + t1) * 0.5)
			local xm, ym = p2dEval0(c, tm)
			local a = p2dDist(x0, y0, x1, y1)
			local b = f32(p2dDist(x0, y0, xm, ym) + p2dDist(xm, ym, x1, y1))
			if depth >= 30 or f32(b - a) < P2D_TOL then return b end
			return f32(rec(t0, tm, x0, y0, xm, ym, depth + 1) + rec(tm, t1, xm, ym, x1, y1, depth + 1))
		end
		local x0, y0 = p2dEval0(c, 0)
		local x1, y1 = p2dEval0(c, 1)
		return rec(0, 1, x0, y0, x1, y1, 0)
	end

	local P2D_SIXTH = f32(1 / 6)
	local function p2dArcU(c: any, s: number): number
		local d2x, d2y = f32(c.c2x * 2), f32(c.c2y * 2)
		local d3x, d3y
		if c.n == 4 then d3x, d3y = f32(c.c3x * 3), f32(c.c3y * 3) end
		local function inv(u: number): number
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
			u = f32(u + f32(f32(f32(k1 + f32(2 * f32(k2 + k3))) + k4) * P2D_SIXTH))
		end
		return u
	end

	local function p2dCurveLength(segs: { any }): number
		local t = 0
		for _, c in ipairs(segs) do
			c.len = c.len or p2dSeglen(c)
			t = f32(t + c.len)
		end
		return t
	end

	local function p2dLocate(segs: { any }, t: number): (any, number)
		t = f32(t)
		if t < 0 then t = 0 elseif t > 1 then t = 1 end
		local n = #segs
		local x = f32(t * n)
		local k = math.min(math.floor(x), n - 1)
		return segs[k + 1], f32(x - k)
	end

	local function p2dLocateArc(segs: { any }, t: number): (any, number)
		t = f32(t)
		if t < 0 then t = 0 elseif t > 1 then t = 1 end
		local L = p2dCurveLength(segs)
		local s = f32(t * L)
		for _, c in ipairs(segs) do
			if s <= c.len then
				if c.n == 2 then return c, f32(s / c.len) end
				return c, p2dArcU(c, s)
			end
			s = f32(s - c.len)
		end
		return segs[1], 0
	end

	local function p2dBuildSegments(cps: { any }, W: number, H: number): any
		local pts = {}
		for i, cp in ipairs(cps) do
			local zero = { 0, 0, 0, 0 }
			local pos = (cp and (p2dUDim2Vals(cp.Position) or p2dUDim2Vals(cp[1]))) or zero
			local left = (cp and (p2dUDim2Vals(cp.LeftTangent) or p2dUDim2Vals(cp[2]))) or zero
			local right = (cp and (p2dUDim2Vals(cp.RightTangent) or p2dUDim2Vals(cp[3]))) or zero
			local px, py = p2dResolve(pos, W, H)
			local lx, ly = p2dResolve(left, W, H)
			local rx, ry = p2dResolve(right, W, H)
			pts[i] = { px, py, lx, ly, rx, ry }
		end
		local segs: any = {}
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
				table.insert(s, f32(a[1] + a[5])); table.insert(s, f32(a[2] + a[6]))
			end
			if b[3] ~= 0 or b[4] ~= 0 then
				table.insert(s, f32(b[1] + b[3])); table.insert(s, f32(b[2] + b[4]))
			end
			table.insert(s, b[1]); table.insert(s, b[2])
			segs[i] = p2dCoeffs(s)
		end
		if hx0 then segs.hull = { hx0, hy0, hx1, hy1 } end
		return segs
	end

	local function isGuiObject(cls: string?): boolean
		if not cls then return false end
		return cls == "Frame" or cls == "TextButton" or cls == "TextLabel"
			or cls == "ImageButton" or cls == "ImageLabel" or cls == "TextBox"
			or cls == "ScrollingFrame" or cls == "ViewportFrame" or cls == "CanvasGroup"
			or cls == "VideoFrame" or cls == "GuiObject" or cls == "GuiButton" or cls == "GuiLabel"
	end

	local function getInstProp(inst: any, name: string): any
		if inst == nil then return nil end
		local wp = instanceWrittenProps[inst]
		if wp and wp[name] ~= nil then
			return wp[name]
		end
		local ok, val = pcall(function() return inst[name] end)
		if ok then return val end
		return nil
	end

	local function getGuiUDim2(v: any): (number, number, number, number)
		if v == nil then return 0, 0, 0, 0 end
		local ok, sx, ox, sy, oy = pcall(function()
			return tonumber(v.X.Scale) or 0, tonumber(v.X.Offset) or 0, tonumber(v.Y.Scale) or 0, tonumber(v.Y.Offset) or 0
		end)
		if ok then return sx, ox, sy, oy end
		return 0, 0, 0, 0
	end

	local function getGuiVec2(v: any): (number, number)
		if v == nil then return 0, 0 end
		local ok, x, y = pcall(function()
			return tonumber(v.X) or 0, tonumber(v.Y) or 0
		end)
		if ok then return x, y end
		return 0, 0
	end

	local function clampGui(v: number, lo: number, hi: number): number
		if v < lo then return lo elseif v > hi then return hi else return v end
	end

	local computeAbsoluteSize, computeAbsolutePosition

	computeAbsoluteSize = function(inst: any): (number, number)
		if not inst then return 0, 0 end
		local cls = instanceClass[inst]
		if cls == "ScreenGui" or cls == "GuiMain" then
			return 1920, 1080
		end
		if not isGuiObject(cls) then return 0, 0 end

		local par = parentOf[inst]
		local parW, parH = 1920, 1080
		if par then
			parW, parH = computeAbsoluteSize(par)
		end

		local sx, ox, sy, oy = getGuiUDim2(getInstProp(inst, "Size"))
		local w = sx * parW + ox
		local h = sy * parH + oy

		local kids = parentChildren[inst]
		if kids then
			for _, kid in ipairs(kids) do
				local kcls = instanceClass[kid]
				if kcls == "UISizeConstraint" then
					local minX, minY = getGuiVec2(getInstProp(kid, "MinSize"))
					local maxX, maxY = getGuiVec2(getInstProp(kid, "MaxSize"))
					if maxX == 0 and maxY == 0 then maxX, maxY = 1e9, 1e9 end
					w = clampGui(w, minX, maxX)
					h = clampGui(h, minY, maxY)
				elseif kcls == "UIScale" then
					local sc = tonumber(getInstProp(kid, "Scale")) or 1
					w = w * sc
					h = h * sc
				end
			end
		end

		return math.floor(w + 0.5), math.floor(h + 0.5)
	end

	computeAbsolutePosition = function(inst: any): (number, number)
		if not inst then return 0, 0 end
		local cls = instanceClass[inst]
		if cls == "ScreenGui" or cls == "GuiMain" then
			return 0, 0
		end
		if not isGuiObject(cls) then return 0, 0 end

		local par = parentOf[inst]
		local parX, parY = 0, 0
		local parW, parH = 1920, 1080
		if par then
			parX, parY = computeAbsolutePosition(par)
			parW, parH = computeAbsoluteSize(par)
		end

		local sx, ox, sy, oy = getGuiUDim2(getInstProp(inst, "Position"))
		local curW, curH = computeAbsoluteSize(inst)
		local apX, apY = getGuiVec2(getInstProp(inst, "AnchorPoint"))

		local x = parX + sx * parW + ox - apX * curW
		local y = parY + sy * parH + oy - apY * curH

		return math.floor(x + 0.5), math.floor(y + 0.5)
	end

	local INSTANCE_EVENT_NAMES: { [string]: boolean } = {
		FocusLost = true, FocusNear = true,
		MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true,
		MouseButton2Click = true, MouseButton2Down = true, MouseButton2Up = true,
		MouseEnter = true, MouseLeave = true,
		MouseMoved = true, MouseWheelForward = true, MouseWheelBackward = true,
		Activated = true, DebounceTimerChanged = true,
		SelectionGained = true, SelectionLost = true,
		InputBegan = true, InputEnded = true, InputChanged = true,
		TouchTap = true, TouchStarted = true, TouchEnded = true, TouchMoved = true,
		ReturnPressedFromAutocomplete = true,
		Triggered = true, PromptButtonHoldBegan = true, PromptButtonHoldEnded = true,
		PromptShown = true, PromptHidden = true, PromptTriggered = true,
		Equipped = true, Unequipped = true,
		Loaded = true, Played = true, Paused = true, Ended = true,
		Looped = true, Stopped = true,
		StateChanged = true, StateEntered = true,
		Died = true, Seated = true, Jumping = true, FreeFalling = true, Running = true,
		Touched = true, TouchEnded = true,
		TargetFilterChanged = true,
	}

	local function instanceChildrenContains(list: { any }, child: any): boolean
		for _, existing in ipairs(list) do
			if existing == child then
				return true
			end
		end
		return false
	end

	local CLASS_ANCESTORS: { [string]: { string } } = {
		DataModel = { "Instance" },
		Workspace = { "Instance" },
		Camera = { "Instance" },
		Terrain = { "Instance" },
		Folder = { "Instance" },
		Model = { "PVInstance", "Instance" },
		Part = { "BasePart", "PVInstance", "Instance" },
		Humanoid = { "Instance" },
		Player = { "Instance" },
		Tool = { "Model", "PVInstance", "Instance" },
	}

	local function isA(selfClass: string, asked: string): boolean
		if asked == selfClass or asked == "Instance" then
			return true
		end
		if ClassData.isA(selfClass, asked) then
			return true
		end
		local ancestors = CLASS_ANCESTORS[selfClass]
		if not ancestors then
			return false
		end
		for _, base in ipairs(ancestors) do
			if base == asked then
				return true
			end
		end
		return false
	end

	local function canonicalMember(key: string, ...: any): string
		local lower = string.lower(key)

		local n = select("#", ...)
		for i = 1, n do
			local t = select(i, ...)
			if type(t) == "table" and rawget(t, key) ~= nil then
				return key
			end
		end
		for i = 1, n do
			local t = select(i, ...)
			if type(t) == "table" then
				for name in pairs(t) do
					if type(name) == "string" and string.lower(name) == lower then
						return name
					end
				end
			end
		end
		return key
	end

	local INSTANCE_BUILTIN_KEYS: { [string]: boolean } = {
		ClassName = true, Name = true, Parent = true, Archivable = true,
		Sandboxed = true, IsInSandbox = true,
	}
	local SERVICE_BUILTIN_KEYS: { [string]: boolean } = {
		ClassName = true, Name = true, Parent = true, Archivable = true,
		Sandboxed = true, IsInSandbox = true,
		GetPropertyChangedSignal = true, GetAttributeChangedSignal = true,
	}
	local SERVICE_NAME_KEYS: { [string]: boolean } = {}
	for _, serviceName in ipairs(Services.NAMES) do
		SERVICE_NAME_KEYS[serviceName] = true
	end
	local GAME_INDEX_KEYS: { [string]: boolean } = {
		Clone = true, GetService = true, FindService = true,
		PlaceId = true, GameId = true, JobId = true, CreatorId = true,
		CreatorType = true, PlaceVersion = true, Genre = true,
		PrivateServerId = true, PrivateServerOwnerId = true, MaxPlayers = true,
		ClassName = true, Name = true, Workspace = true,
		HttpGet = true, HttpGetAsync = true, HttpPost = true, HttpPostAsync = true,
		IsLoaded = true, Destroy = true, Shutdown = true, ClearAllChildren = true,
		BindToClose = true, GetPropertyChangedSignal = true,
		GetAttributeChangedSignal = true, Parent = true,
	}

	local function instanceMethods(
		basePath: string,
		className: string,
		children: { [string]: any }?,
		special: { [string]: any }?,
		dynamic: { any }?
	): { [string]: any }
		local order: { string } = {}
		if children then
			for name in pairs(children) do
				order[#order + 1] = name
			end
			table.sort(order)
		end

		local function childByMethod(name: string, method: string): any
			if special and special[name] ~= nil then
				return special[name]
			end
			local desc = children and children[name]
			if not desc then
				return nil
			end
			local expression = string.format("%s:%s(%s)", basePath, method, Serializer.stringLiteral(name))
			return makeInstance(expression, desc.className, desc.properties)
		end

		local function childField(name: string): any
			if special and special[name] ~= nil then
				return special[name]
			end
			local desc = children and children[name]
			if not desc then
				return nil
			end
			return makeInstance(basePath .. "." .. name, desc.className, desc.properties)
		end

		local function dynamicByName(asked: string): any
			if dynamic == nil then
				return nil
			end
			for _, child in ipairs(dynamic) do
				if child ~= nil then
					local okName, childName = pcall(function()
						return (Spy.pathOf(child) and child.Name) or nil
					end)
					if okName and childName ~= nil then
						local resolved = Spy.unwrap(childName)
						if resolved == nil then
							resolved = childName
						end
						if tostring(resolved) == asked then
							return child
						end
					end
				end
			end
			return nil
		end

		local function dynamicByClass(matches: (string) -> boolean): any
			if dynamic == nil then
				return nil
			end
			for _, child in ipairs(dynamic) do
				if child ~= nil then
					local okClass, childClass = pcall(function()
						return (Spy.pathOf(child) and child.ClassName) or nil
					end)
					if okClass and childClass ~= nil then
						local resolved = Spy.unwrap(childClass)
						if resolved ~= nil and type(resolved) == "string" and matches(resolved) then
							return child
						end
					end
				end
			end
			return nil
		end

		local function childrenList(): { any }
			local out: { any } = {}
			for _, name in ipairs(order) do
				local child = childField(name)
				if child ~= nil then
					out[#out + 1] = child
				end
			end
			if dynamic then
				for _, child in ipairs(dynamic) do
					if child ~= nil then
						out[#out + 1] = child
					end
				end
			end
			return out
		end

		local function voxelGrid(region: any, resolution: any, fill: any): { any }
			local step = tonumber(Spy.unwrap(resolution)) or 4
			if step <= 0 then
				step = 4
			end
			local size = if region ~= nil then region.Size else nil
			local function extent(axis: string): number
				local value = if size ~= nil then tonumber(size[axis]) else nil
				return math.max(1, math.floor((value or 0) / step))
			end
			local grid: { any } = {}
			for x = 1, extent("X") do
				local plane: { any } = {}
				for y = 1, extent("Y") do
					local column: { any } = {}
					for z = 1, extent("Z") do
						column[z] = fill
					end
					plane[y] = column
				end
				grid[x] = plane
			end
			return grid
		end

		return {
			WaitForChild = function(_self: any, name: any, timeout: any?): any
				local asked = tostring(Spy.unwrap(name) or "")

				local live = dynamicByName(asked)
				if live ~= nil then
					return live
				end
				local child = childByMethod(asked, "WaitForChild")
				if child ~= nil then
					return child
				end

			if timeout ~= nil then
				return nil
			end
			local fake = makeInstance(
				string.format("%s:WaitForChild(%s)", basePath, Serializer.stringLiteral(asked)),
				"Instance",
				{ Name = asked }
			)

			Symbol.tag(fake, {
				kind = "instance",
				expression = string.format("%s:WaitForChild(%s)", basePath, Serializer.stringLiteral(asked)),
				typeName = "Instance",
				detail = { className = "Instance", unknownMember = asked, ownerName = className },
			})
			return fake
		end,
			FindFirstChild = function(_self: any, name: any, recursive: any): any
				local asked = tostring(Spy.unwrap(name) or "")

				local live = dynamicByName(asked)
				if live ~= nil then
					return live
				end
				local child = childByMethod(asked, "FindFirstChild")
				if child ~= nil then
					return child
				end

				if Spy.unwrap(recursive) == true then
					local stack: { any } = childrenList()
					local seen: { [any]: boolean } = {}
					while #stack > 0 do
						local node = table.remove(stack)
						if node ~= nil and not seen[node] then
							seen[node] = true
							local nodeName = nil
							local nodeOk, nodeRes = pcall(function()
								return node.Name
							end)
							if nodeOk and type(nodeRes) == "string" then
								nodeName = nodeRes
							end
							if nodeName == asked then
								return node
							end
							local nodeOk2, descendants = pcall(function()
								return node:GetChildren()
							end)
							if nodeOk2 and type(descendants) == "table" then
								for _, d in ipairs(descendants) do
									stack[#stack + 1] = d
								end
							end
						end
					end
				end

				return nil
			end,
			FindFirstChildOfClass = function(_self: any, class: any): any
				local asked = tostring(Spy.unwrap(class) or "")
				for _, name in ipairs(order) do
					local desc = children and children[name]
					if desc and desc.className == asked then
						return childByMethod(name, "FindFirstChildOfClass")
					end
				end

				return dynamicByClass(function(className: string): boolean
					return className == asked
				end)
			end,
			FindFirstChildWhichIsA = function(_self: any, class: any): any
				local asked = tostring(Spy.unwrap(class) or "")
				for _, name in ipairs(order) do
					local desc = children and children[name]
					if desc and isA(desc.className, asked) then
						return childByMethod(name, "FindFirstChildWhichIsA")
					end
				end
				return dynamicByClass(function(className: string): boolean
					return isA(className, asked)
				end)
			end,
			GetChildren = function(): { any }
				return childrenList()
			end,
			GetDescendants = function(): { any }

				local out: { any } = {}
				local seen: { [any]: boolean } = {}
				local stack: { any } = childrenList()
				while #stack > 0 do
					local child = table.remove(stack)
					if child ~= nil and not seen[child] then
						seen[child] = true
						out[#out + 1] = child
						local deeper = parentChildren[child]
						if deeper then
							for i = #deeper, 1, -1 do
								stack[#stack + 1] = deeper[i]
							end
						end
					end
				end
				return out
			end,
			IsA = function(_self: any, class: any): boolean
				return isA(className, tostring(Spy.unwrap(class) or ""))
			end,
			IsDescendantOf = function(): boolean
				return false
			end,
			FindFirstAncestor = function(): any
				return nil
			end,
			Clone = function(_self: any): any
				return makeInstance(basePath .. ":Clone()", className)
			end,
			Destroy = function() end,
			ClearAllChildren = function() end,
			PivotTo = function() end,
			SetAttribute = function() end,
			GetAttribute = function(): any
				return nil
			end,

			GetFullName = function(): string
				local service = string.match(basePath, "GetService%([\"']([%w_]+)[\"']%)")
				if service then
					return service
				end
				return string.match(basePath, "%.([%w_]+)$") or className
			end,

			ReadVoxels = function(_self: any, region: any, resolution: any): (any, any)

				local air = EnumItem.new("Air", 1792)
				return voxelGrid(region, resolution, air), voxelGrid(region, resolution, 0)
			end,
			WriteVoxels = function(): any
				return nil
			end,
			FillBlock = function(): any
				return nil
			end,
			FillRegion = function(): any
				return nil
			end,
			FillBall = function(): any
				return nil
			end,
			CountCells = function(): number
				return 0
			end,
		}
	end

	makeInstance = function(
		path: string,
		className: string,
		properties: { [string]: any }?,
		children: { [string]: any }?,
		extraOnWrite: ((key: string, proxy: any) -> ())?,
		parent: any?
	): (any, any)

		local dynamicChildren: { any } = {}
		local methods = instanceMethods(path, className, children, nil, dynamicChildren)
		require("./fidelity").registerTree(methods)

		local signals: { [string]: any } = {}
		local bindableCallbacks: { (any) -> () }? = nil

		local instanceRenderId: number? = nil

		local function getSignal(prop: string, renderExpr: string?): any
			if signals[prop] == nil then
				local signalName = path .. ".GetPropertyChangedSignal(\"" .. prop .. "\")"
				signals[prop] = Signal.new(signalName, {
					trace = trace,
					nest = nest,
					connectExpr = renderExpr or signalName,
					baseId = instanceRenderId,
					event = prop,
				})
			end
			return signals[prop]
		end
		methods.GetPropertyChangedSignal = function(_self: any, prop: any): any
			return getSignal(tostring(Spy.unwrap(prop) or ""))
		end

		local attributes: { [string]: any } = {}
		methods.SetAttribute = function(self: any, key: any, value: any): any
			local name = tostring(Spy.unwrap(key) or "")
			if name == "" then
				error("Attribute name must be a non-empty string", 2)
			end
			attributes[name] = value
			local changed = getSignal("Attribute" .. name)
			changed._fire(value)
			local all = getSignal("Changed")
			all._fire(name, value)
			return nil
		end
		methods.GetAttribute = function(_self: any, key: any): any
			return attributes[tostring(Spy.unwrap(key) or "")]
		end

		if properties ~= nil and materializedDefaults[className] ~= nil then
			local merged: { [string]: any } = {}
			for k, v in pairs(materializedDefaults[className]) do
				merged[k] = v
			end
			for k, v in pairs(properties) do
				merged[k] = v
			end
			properties = merged
		end

		local pendingVelocity: any = nil
		local simulatedPosition: any = nil

		local destroyed = false

		local archivable = true

		local writtenProps: { [string]: any } = {}
		local instance: any = nil

		local instanceConfig
		instanceConfig = {
			trace = trace,
			nest = nest,
			maxDepth = config.maxDepth,
			softInstanceCall = config.softInstanceCall,
			onWrite = function(_proxy: any, key: any, value: any)
				local name = if type(key) == "string"
					then canonicalMember(key, methods, properties, INSTANCE_BUILTIN_KEYS, RBX_SIGNAL_PROPS, INSTANCE_EVENT_NAMES)
					else tostring(key)

				if name == "ClassName" then

					error("Unable to assign property 'ClassName'. Property is read only", 0)
				end

				if signals[name] ~= nil or RBX_SIGNAL_PROPS[name] then
					error(string.format("%s cannot be assigned to", name), 2)
				end
				if name == "Position" or name == "Size" then

					local tn = Symbol.typeName(value)
					if tn ~= "Vector3" and tn ~= "UDim2" then
						error(string.format(
							"Unable to assign property '%s'. expected Vector3 or UDim2, got %s",
							name, tn
						), 0)
					end
				elseif name == "Orientation" then
					if Symbol.typeName(value) ~= "Vector3" then
						error(string.format(
							"Unable to assign property 'Orientation'. expected Vector3, got %s",
							Symbol.typeName(value)
						), 0)
					end
				elseif name == "CFrame" then
					if Symbol.typeName(value) ~= "CFrame" then
						error(string.format(
							"Unable to assign property 'CFrame'. expected CFrame, got %s",
							Symbol.typeName(value)
						), 0)
					end
				end
				local signal = signals[name]
				if signal then
					signal._fire(value)
				end
				if name == "Velocity" then
					pendingVelocity = value
					simulatedPosition = nil
				end

				if name ~= "Parent" then
					writtenProps[name] = value
				end
				if name == "Name" then

					pcall(Spy.rename, _proxy, tostring(value))
				end
				if name == "Parent" then

					if destroyed then

						local renderedPath = Spy.pathOf(_proxy) or path
						local currentName = string.match(renderedPath, "([%w_]+)$") or className
						error(string.format(
							"The Parent property of %s is locked",
							tostring(currentName)
						), 2)
					end

					local unwrappedNew = Spy.unwrap(value) or value
					if unwrappedNew ~= nil and not Spy.is(unwrappedNew) then
						error(string.format(
							"Unable to assign property 'Parent'. expected Instance, got %s",
							type(unwrappedNew)
						), 0)
					end

					local oldParent = parentOf[_proxy]
					if oldParent and parentChildren[oldParent] then
						local oldSlot = parentChildren[oldParent]
						for i = #oldSlot, 1, -1 do
							if oldSlot[i] == _proxy then
								table.remove(oldSlot, i)
							end
						end
					end
					parentOf[_proxy] = unwrappedNew
					if unwrappedNew ~= nil then
						local slot = parentChildren[unwrappedNew]
						if slot and not instanceChildrenContains(slot, _proxy) then
							slot[#slot + 1] = _proxy
						end
					end
				end
				if name == "Archivable" then
					archivable = value == true
				end

				getSignal("Changed")._fire(name, value)
				if extraOnWrite then
					extraOnWrite(name, _proxy)
				end
			end,
			onRead = function(_proxy: any, key: any, value: any): (any, boolean)
				if type(key) == "string" then
					local canonical = canonicalMember(key, methods, properties, INSTANCE_BUILTIN_KEYS)

					if canonical ~= key and writtenProps[canonical] ~= nil then
						return writtenProps[canonical], true
					end
					key = canonical
				end
				if key == "Parent" then

					local live = parentOf[_proxy]
					if live ~= nil then
						return live, true
					end
					if destroyed or parent == nil then
						return nil, true
					end
					return value, false
				end
				if key == "Position" then
					if simulatedPosition ~= nil then
						return simulatedPosition, true
					end
					if pendingVelocity ~= nil then
						local velocity = pendingVelocity
						pendingVelocity = nil
						simulatedPosition = value + velocity * 0.1
						return simulatedPosition, true
					end
				end
				return nil, false
			end,				onIndex = function(basePath: string, key: any): (boolean, any)
					if type(key) ~= "string" then
						return false, nil
					end

					key = canonicalMember(key, methods, properties, children,
						macroOverrides, INSTANCE_BUILTIN_KEYS, RBX_SIGNAL_PROPS,
						INSTANCE_EVENT_NAMES)

					if key ~= "Parent" then
						local macroValue = macroOverrides[key]
						if macroValue ~= nil then
							return true, macroValue
						end
					end					local method = methods[key]
					if method ~= nil then
						if type(method) == "function" then
							local wrapped = recorded(basePath, key, method)

							require("./fidelity").register(wrapped, key)
							return true, wrapped
						end
					return true, method
					end					if (key == "AbsolutePosition" or key == "AbsoluteSize") and (isGuiObject(className) or className == "ScreenGui" or className == "GuiMain") then
						local x, y
						if key == "AbsolutePosition" then
							x, y = computeAbsolutePosition(instance)
						else
							x, y = computeAbsoluteSize(instance)
						end
						return true, dtypes.Vector2.new(x, y)
					end

					if writtenProps[key] ~= nil then
						return true, writtenProps[key]
					end

					if properties and properties[key] ~= nil then
						return true, properties[key]
					end					local childDesc = children and children[key]
					if childDesc then

						return true, makeInstance(basePath .. "." .. key, childDesc.className, childDesc.properties, nil, childDesc.onWrite, instance)
					end

				if key == "ClassName" then
					return true, className
				elseif key == "Name" then
					return true, string.match(basePath, "([%w_]+)$") or className
				elseif key == "Parent" then

					if destroyed then
						return true, nil
					end

					local liveParent = parentOf[instance]
					if liveParent ~= nil then
						return true, liveParent
					end
					return true, parent
				elseif key == "Changed" or key == "AncestryChanged" or key == "ChildAdded"
					or key == "ChildRemoved" or key == "DescendantAdded" or key == "DescendantRemoving"
					or key == "AttributeChanged" then

					return true, getSignal(tostring(key), path .. "." .. tostring(key))
				elseif key == "Archivable" then
					return true, archivable
				elseif key == "Sandboxed" or key == "IsInSandbox" then

					return true, false
				end

				if className == "BindableEvent" then
					if key == "Event" then

						if not bindableCallbacks then
							bindableCallbacks = {}
						end
						local signalCallbacks = bindableCallbacks
						local signal = Signal.new(path .. ".Event")
						signal.Connect = function(_self: any, callback: any): any
							signalCallbacks[#signalCallbacks + 1] = callback
							local connection: any
							connection = {
								Connected = true,
								Disconnect = function()
									connection.Connected = false
								end,
							}
							Symbol.tag(connection, {
								kind = "datatype",
								expression = path .. ".Event:Connect(function() end --[[ callback ]])",
								typeName = "RBXScriptConnection",
							})
							return connection
						end
						return true, signal
					elseif key == "Fire" then
						return true, recorded(basePath, "Fire", function(_self: any, ...: any)
							if not bindableCallbacks then return end
							for _, callback in ipairs(bindableCallbacks) do
								pcall(callback, ...)
							end
						end)
					end
				end

				if INSTANCE_EVENT_NAMES[tostring(key)] then
					return true, getSignal(tostring(key), path .. "." .. tostring(key))
				end

				if className == "Humanoid" and (key == "StateChanged" or key == "StateEntered"
					or key == "Died" or key == "Seated" or key == "Jumping"
					or key == "FreeFalling" or key == "Running") then
					return true, getSignal(tostring(key), path .. "." .. tostring(key))
				end

				if className == "Camera" then
					local dtypes = require("./datatypes").build()
					local cameraProjection = {
						WorldToScreenPoint = true,
						WorldToViewportPoint = true,
					}
					if type(key) == "string" and cameraProjection[key] then
						return true, recorded(basePath, key, function(_self: any, worldPoint: any): any
							local _ = worldPoint
							return dtypes.Vector3.new(640, 360, 0)
						end)
					end
					if key == "ScreenPointToRay" or key == "ViewportPointToRay" then
						return true, recorded(basePath, key, function(_self: any, x: any, y: any): any
							return dtypes.Ray.new(dtypes.Vector3.new(tonumber(x) or 0, tonumber(y) or 0, 0), dtypes.Vector3.new(0, 0, -1))
						end)
					end
				end

			if className == "RemoteEvent" or className == "UnreliableRemoteEvent" then
				if key == "OnServerEvent" or key == "OnClientEvent" then
					return true, getSignal(tostring(key), path .. "." .. tostring(key))
				end
				if key == "FireServer" or key == "FireClient" or key == "FireAllClients" then
					return true, recorded(basePath, key, function(_self: any, ...: any): any
						return nil
					end)
				end
			elseif className == "RemoteFunction" then
				if key == "OnServerInvoke" or key == "OnClientInvoke" then

					return true, nil
				end
				if key == "InvokeServer" or key == "InvokeClient" then
					return true, recorded(basePath, key, function(_self: any, ...: any): any

						return Spy.new(basePath .. ":" .. tostring(key) .. "(...)", config, nil, false, 0)
					end)
				end
			elseif className == "BindableFunction" then
				if key == "OnInvoke" then
					return true, nil
				end
				if key == "Invoke" then
					return true, recorded(basePath, key, function(_self: any, ...: any): any

						local current: any = nil
						local okRead, readBack = pcall(function()
							return (_self :: any).OnInvoke
						end)
						if okRead then
							if type(readBack) == "function" and not Spy.is(readBack) then
								current = readBack
							else
								local unwrapped = Spy.unwrap(readBack)
								if type(unwrapped) == "function" then
									current = unwrapped
								end
							end
						end
						if current == nil then
							return nil
						end
						local results = table.pack(pcall(current, ...))
						if results[1] then
							return table.unpack(results, 2, results.n)
						end
						return nil
					end)
				end
			end

				local memberChild = makeInstance(
					string.format("%s.%s", basePath, tostring(key)),
					"Instance",
					{ Name = tostring(key) }
				)
				Symbol.tag(memberChild, {
					kind = "instance",
					expression = string.format("%s.%s", basePath, tostring(key)),
					typeName = "Instance",
					detail = {
						unknownMember = tostring(key),
						ownerName = className,
					},
				})
				return true, memberChild
			end,
			onCall = function(): (boolean, any)
				return false, nil
			end,
		}			instance = Spy.new(path, instanceConfig, nil, false, 0)

		instanceRenderId = Spy.renderIdOf(instance)
		Symbol.tag(instance, {
			kind = "instance",
			expression = path,
			typeName = "Instance",
			detail = { className = className },
		})
		parentChildren[instance] = dynamicChildren
		instanceClass[instance] = className
		instanceWrittenProps[instance] = writtenProps

		if parent ~= nil then
			parentOf[instance] = parent
		end
		methods.IsDescendantOf = function(_self: any, ancestor: any): boolean
			local node = parentOf[instance]
			local target = Spy.unwrap(ancestor) or ancestor
			local guard = 0
			while node ~= nil and guard < 64 do
				if node == target or node == ancestor then
					return true
				end
				node = parentOf[node]
				guard += 1
			end
			return false
		end
		methods.FindFirstAncestor = function(_self: any, name: any): any
			local wanted = tostring(Spy.unwrap(name) or "")
			local node = parentOf[instance]
			local guard = 0
			while node ~= nil and guard < 64 do
				local ok, value = pcall(function()
					return (Spy.pathOf(node) and node.Name) or nil
				end)
				if ok and type(value) == "string" and string.match(Spy.pathOf(node) or "", "([%w_]+)$") == wanted then
					return node
				end
				node = parentOf[node]
				guard += 1
			end
			return nil
		end

		local function liveNameOf(node: any): string
			local ok, value = pcall(function()
				return node.Name
			end)
			if ok then
				local unwrapped = Spy.unwrap(value)
				if type(unwrapped) == "string" and unwrapped ~= "" then
					return unwrapped
				end
			end
			return className
		end
		methods.GetFullName = function(_self: any): string
			local segments = { liveNameOf(instance) }
			local node = parentOf[instance]
			local guard = 0
			while node ~= nil and guard < 64 do
				local name = liveNameOf(node)

				if name == "DataModel" or name == "game" or name == "Game" then
					break
				end
				table.insert(segments, 1, name)
				node = parentOf[node]
				guard += 1
			end
			return table.concat(segments, ".")
		end
		if className == "Humanoid" then

			local function healthNow(): number
				local ok, value = pcall(function()
					return instance.Health
				end)
				if ok then
					local unwrapped = tonumber(Spy.unwrap(value))
					if unwrapped then
						return unwrapped
					end
				end
				return 100
			end
			methods.TakeDamage = function(_self: any, amount: any): any
				local damage = tonumber(Spy.unwrap(amount)) or 0
				local current = healthNow()
				if current <= 0 then

					return nil
				end
				instance.Health = math.max(0, current - math.max(0, damage))
				return nil
			end
			methods.MoveTo = function(): any
				return nil
			end
			methods.Move = function(): any
				return nil
			end
			methods.ChangeState = function(): any
				return nil
			end
			methods.GetState = function(): any
				return EnumItem.new("Running", 8)
			end
			methods.EquipTool = function(): any
				return nil
			end
			methods.UnequipTools = function(): any
				return nil
			end
			methods.GetPlayingAnimationTracks = function(): { any }
				return {}
			end
		end
		if className == "Path2D" then
			local controlPoints: { any } = {}
			local cachedSegs: any = nil
			local cachedW: number? = nil
			local cachedH: number? = nil

			local function getPathFrameSize(): (number, number)
				local par = parentOf[instance]
				if par then
					local W, H = computeAbsoluteSize(par)
					if W > 0 and H > 0 then return W, H end
					local psz = instanceWrittenProps[par] and instanceWrittenProps[par].Size
					if psz then
						local _, ox, _, oy = getGuiUDim2(psz)
						if ox > 0 and oy > 0 then return ox, oy end
					end
				end
				return 1920, 1080
			end

			local function getSegs(): any
				local W, H = getPathFrameSize()
				if cachedSegs and cachedW == W and cachedH == H then
					return cachedSegs
				end
				local segs = p2dBuildSegments(controlPoints, W, H)
				cachedSegs, cachedW, cachedH = segs, W, H
				return segs
			end

			methods.SetControlPoints = function(_self: any, points: any): any
				controlPoints = {}
				if type(points) == "table" then
					for _, p in ipairs(points) do
						controlPoints[#controlPoints + 1] = p
					end
				end
				cachedSegs = nil
				return nil
			end
			methods.GetControlPoints = function(_self: any): { any }
				return table.clone(controlPoints)
			end
			methods.GetMaxControlPoints = function(_self: any): number
				return 100
			end
			methods.GetPointPosition = function(_self: any, index: any): any
				local i = tonumber(Spy.unwrap(index)) or 1
				local pt = controlPoints[i]
				if pt ~= nil then
					return pt
				end
				return dtypes.Vector3.new(0, 0, 0)
			end
			methods.GetLength = function(_self: any): number
				local segs = getSegs()
				if not segs or #segs == 0 then return 0 end
				return p2dCurveLength(segs)
			end
			methods.GetSegmentLength = function(_self: any, seg: any): number
				local s = tonumber(Spy.unwrap(seg)) or 1
				local segs = getSegs()
				if not segs or not segs[s] then return 0 end
				segs[s].len = segs[s].len or p2dSeglen(segs[s])
				return segs[s].len
			end
			methods.GetPositionOnCurve = function(_self: any, t: any): any
				local segs = getSegs()
				if not segs or #segs == 0 then return dtypes.UDim2.new(0, 0, 0, 0) end
				local c, u = p2dLocate(segs, tonumber(Spy.unwrap(t)) or 0)
				if not c then return dtypes.UDim2.new(0, 0, 0, 0) end
				local x, y = p2dEval(c, u)
				local W, H = getPathFrameSize()
				return dtypes.UDim2.new(f32(x / W), 0, f32(y / H), 0)
			end
			methods.GetTangentOnCurve = function(_self: any, t: any): any
				local segs = getSegs()
				if not segs or #segs == 0 then return dtypes.Vector2.new(0, 0) end
				local c, u = p2dLocate(segs, tonumber(Spy.unwrap(t)) or 0)
				if not c then return dtypes.Vector2.new(0, 0) end
				local x, y = p2dTangent(c, u)
				return dtypes.Vector2.new(x, y)
			end
			methods.GetPositionOnCurveArcLength = function(_self: any, t: any): any
				local segs = getSegs()
				if not segs or #segs == 0 then return dtypes.UDim2.new(0, 0, 0, 0) end
				local c, u = p2dLocateArc(segs, tonumber(Spy.unwrap(t)) or 0)
				if not c then return dtypes.UDim2.new(0, 0, 0, 0) end
				local x, y = p2dEval(c, u)
				local W, H = getPathFrameSize()
				return dtypes.UDim2.new(f32(x / W), 0, f32(y / H), 0)
			end
			methods.GetTangentOnCurveArcLength = function(_self: any, t: any): any
				local segs = getSegs()
				if not segs or #segs == 0 then return dtypes.Vector2.new(0, 0) end
				local c, u = p2dLocateArc(segs, tonumber(Spy.unwrap(t)) or 0)
				if not c then return dtypes.Vector2.new(0, 0) end
				local x, y = p2dTangent(c, u)
				return dtypes.Vector2.new(x, y)
			end
			methods.GetBoundingRect = function(_self: any): any
				local segs = getSegs()
				if not segs or not segs.hull then return dtypes.Rect.new(0, 0, 0, 0) end
				local W, H = getPathFrameSize()
				local h = segs.hull
				return dtypes.Rect.new(f32(h[1] / W), f32(h[2] / H), f32(h[3] / W), f32(h[4] / H))
			end
			methods.GetBoundingBox = function(_self: any): any
				return {
					min = dtypes.Vector3.new(0, 0, 0),
					max = dtypes.Vector3.new(0, 0, 0),
					CFrame = nil,
				}
			end
			methods.Update = function(_self: any): any
				cachedSegs = nil
				return nil
			end
		end
		methods.Destroy = function(_self: any): any
			destroyed = true
			parentOf[instance] = nil

			for _, childList in pairs(parentChildren) do
				for i = #childList, 1, -1 do
					if childList[i] == instance then
						table.remove(childList, i)
					end
				end
			end
			parentChildren[instance] = dynamicChildren

			for _, child in ipairs(dynamicChildren) do
				parentOf[child] = nil
			end
			table.clear(dynamicChildren)
			getSignal("Changed")._fire("Parent", nil)
			return nil
		end

		methods.Clone = function(_self: any): any
			if not archivable then
				return nil
			end
			local clone = makeInstance(path .. ":Clone()", className)

			Spy.markUnique(clone)
			for key, value in pairs(writtenProps) do

				pcall(function()
					clone[key] = value
				end)
			end

			for _, child in ipairs(dynamicChildren) do
				local ok, copy = pcall(function()
					return child:Clone()
				end)
				if ok and copy ~= nil then
					pcall(function()
						copy.Parent = clone
					end)
				end
			end
			return clone
		end
		methods.ClearAllChildren = function(_self: any): any
			for _, child in ipairs(dynamicChildren) do
				parentOf[child] = nil
			end
			table.clear(dynamicChildren)
			getSignal("ChildRemoved")._fire(nil)
			return nil
		end
		return instance, getSignal
	end

	local services: { [string]: any } = {}

	local INSTANCE_SIGNALS: { [string]: boolean } = {
		Changed = true,
		ChildAdded = true,
		ChildRemoved = true,
		DescendantAdded = true,
		DescendantRemoving = true,
		AncestryChanged = true,
		AttributeChanged = true,
	}

	local secretStore: { [string]: { [string]: string } } = {}
	local function makeSecret(secretName: string): any
		local values = secretStore[secretName]
		if values == nil then
			values = {}
			secretStore[secretName] = values
		end
		return Symbol.tag({
			Get = function(_s: any, key: any): string
				return values[tostring(key)] or ""
			end,
			Set = function(_s: any, key: any, value: any)
				values[tostring(key)] = tostring(value)
			end,
			AddPrefix = function(_s: any, prefix: any): any
				return makeSecret(tostring(prefix) .. "-" .. secretName)
			end,
			AddSuffix = function(_s: any, suffix: any): any
				return makeSecret(secretName .. "-" .. tostring(suffix))
			end,
			Clear = function()
				table.clear(values)
			end,
		}, {
			kind = "datatype",
			expression = 'game:GetService("HttpService"):GetSecret('
				.. Serializer.stringLiteral(secretName) .. ")",
			typeName = "Secret",
		})
	end

	local function serviceMethods(name: string, path: string): { [string]: any }
		if name == "CollectionService" then

			local tagsByInstance: { [any]: { string } } = setmetatable({}, { __mode = "k" })
			local function instanceTags(target: any): { string }
				local key = Spy.unwrap(target) or target
				tagsByInstance[key] = tagsByInstance[key] or {}
				return tagsByInstance[key]
			end
			return {
				AddTag = function(_self: any, target: any, tag: any): any
					local wanted = tostring(Spy.unwrap(tag) or "")
					local list = instanceTags(target)
					if not table.find(list, wanted) then
						list[#list + 1] = wanted
					end
					return nil
				end,
				RemoveTag = function(_self: any, target: any, tag: any): any
					local wanted = tostring(Spy.unwrap(tag) or "")
					local list = instanceTags(target)
					local index = table.find(list, wanted)
					if index then
						table.remove(list, index)
					end
					return nil
				end,
				HasTag = function(_self: any, target: any, tag: any): boolean
					local wanted = tostring(Spy.unwrap(tag) or "")
					return table.find(instanceTags(target), wanted) ~= nil
				end,
				GetTags = function(_self: any, target: any): { string }
					local out: { string } = {}
					for _, tag in ipairs(instanceTags(target)) do
						out[#out + 1] = tag
					end
					return out
				end,
				GetTagged = function(_self: any, tag: any): { any }
					return {}
				end,
				GetInstanceAddedSignal = function(_self: any, _tag: any): any
					return Signal.new(path .. ":GetInstanceAddedSignal()")
				end,
				GetInstanceRemovedSignal = function(_self: any, _tag: any): any
					return Signal.new(path .. ":GetInstanceRemovedSignal()")
				end,
			}
		end
		if name == "Workspace" then

			return {
				GetPartsInPart = function(): { any }
					return {}
				end,
				GetPartBoundsInBox = function(): { any }
					return {}
				end,
				GetPartBoundsInRadius = function(): { any }
					return {}
				end,
				Raycast = function(_self: any, origin: any, _direction: any, _params: any): any

					local _ = origin
					return nil
				end,
				RaycastAsync = function(_self: any, origin: any, direction: any, params: any): any
					return nil
				end,
				FindPartsInRegion3 = function(): { any }
					return {}
				end,
			}
		elseif name == "HttpService" then
			local httpService: any = {

				HttpEnabled = false,
				GetAsync = function(_self: any, url: any): string
					return pr(url, "GET")
				end,
				PostAsync = function(_self: any, url: any): string
					return pr(url, "POST")
				end,
				RequestAsync = function(_self: any, request: any): any
					local target = if type(request) == "table" then request.Url else request
					local body = pr(target, "REQUEST")
					return { Success = true, StatusCode = 200, StatusMessage = "OK", Body = body, Headers = {} }
				end,
				JSONEncode = function(_self: any, value: any): string

					local unwrapped = Spy.unwrap(value)
					local ok, encoded = pcall(function()
						local serde = require("@lune/serde")
						return serde.encode("json", unwrapped)
					end)
					return if ok then encoded else "{}"
				end,
				JSONDecode = function(_self: any, text: any, ...: any): any

					local raw = Spy.unwrap(text)
					if type(raw) ~= "string" and type(_self) == "string" then
						raw = Spy.unwrap(_self)
					end
					if type(raw) ~= "string" then
						return {}
					end
					local ok, decoded = pcall(function()
						local serde = require("@lune/serde")
						return serde.decode("json", raw)
					end)

					if not ok or decoded == nil then
						return {}
					end
					return decoded
				end,
				GenerateGUID = function(_self: any, wrapInCurlyBraces: any): string

					local hex = "0123456789ABCDEF"
					local buf = {}
					for i = 1, 32 do
						local n = math.random(1, 16)
						buf[i] = string.sub(hex, n, n)
					end
					local body = table.concat(buf)
					local guid = string.sub(body, 1, 8)
						.. "-" .. string.sub(body, 9, 12)
						.. "-" .. string.sub(body, 13, 16)
						.. "-" .. string.sub(body, 17, 20)
						.. "-" .. string.sub(body, 21, 32)

					local wrap = Spy.unwrap(wrapInCurlyBraces)
					if wrap == false then
						return guid
					end
					return "{" .. guid .. "}"
				end,
				UrlEncode = function(_self: any, text: any): string
					local raw = tostring(Spy.unwrap(text) or "")
					return (string.gsub(raw, "[^%w%-%._~]", function(c)
						return string.format("%%%02X", string.byte(c))
					end))
				end,
				GetSecret = function(_self: any, scope: any): any
					local name = tostring(Spy.unwrap(scope) or "")

					if secretStore[name] == nil then
						error("Secret '" .. name .. "' does not exist", 2)
					end
					return makeSecret(name)
				end,
			}
			return setmetatable(httpService, {
				__index = function(_t: any, key: any): any
					return nil
				end,
			})
		elseif name == "RunService" then
			return {
				IsClient = function(): boolean
					return true
				end,
				IsServer = function(): boolean
					return false
				end,
				IsStudio = function(): boolean
					return false
				end,
				IsRunning = function(): boolean
					return true
				end,
				IsRunMode = function(): boolean
					return false
				end,
			}
		elseif name == "Players" then
			return {

				GetPlayers = function(): { any }
					return { Roblox.localPlayer }
				end,

				MaxPlayers = 100,
				NumPlayers = 1,
				GetPlayerByUserId = function(): any
					return nil
				end,
				GetPlayerFromCharacter = function(): any
					return nil
				end,
				GetUserThumbnailAsync = function(): (string, boolean)
					return "", true
				end,
				GetNameFromUserIdAsync = function(_self: any, userId: any): string

					local _ = userId
					return FAKE.userName
				end,

				GetCharacterAppearanceInfoAsync = function(_self: any, userId: any): { [string]: any }
					local _ = userId
					return {
						assets = {
							{ id = 86500185, name = "Rainbow Shaggy", assetType = { id = 41, name = "HairAccessory" } },
							{ id = 376490373, name = "Robloxian 2.0 Torso", assetType = { id = 27, name = "Torso" } },
						},
						bodyColors = {
							headColorId = 24,
							leftArmColorId = 24,
							leftLegColorId = 119,
							rightArmColorId = 24,
							rightLegColorId = 119,
							torsoColorId = 23,
						},
						scales = {
							bodyType = 0,
							depth = 1,
							head = 1,
							height = 1,
							proportion = 0,
							width = 1,
						},
						emotes = {},
						defaultPantsApplied = false,
						defaultShirtApplied = false,
						playerAvatarType = "R6",
					}
				end,
			}
		elseif name == "MarketplaceService" then
			return {
				GetProductInfo = function(): any
					return { Name = "Asset", Description = "", Creator = { Id = 1, Name = "Roblox" }, PriceInRobux = 0 }
				end,
				UserOwnsGamePassAsync = function(): boolean
					return false
				end,
				PlayerOwnsAsset = function(): boolean
					return false
				end,
			}
		elseif name == "DataStoreService" then

			local function refuseDataStore(name: any, scope: any): never
				local storeName = tostring(Spy.unwrap(name) or "")
				if storeName == "" then
					error("DataStore name can't be empty string", 3)
				end
				local storeScope = Spy.unwrap(scope)
				if storeScope ~= nil and tostring(storeScope) == "" then
					error("DataStore scope can't be empty string", 3)
				end
				error("DataStore can't be accessed from client", 3)
			end
			return {
				GetDataStore = function(_self: any, name: any, scope: any): any
					return refuseDataStore(name, scope)
				end,
				GetGlobalDataStore = function(_self: any): any
					error("DataStore can't be accessed from client", 2)
				end,
				GetOrderedDataStore = function(_self: any, name: any, scope: any): any
					return refuseDataStore(name, scope)
				end,
			}
	elseif name == "TweenService" then
		return {
			Create = function(_self: any, instance: any, tweenInfo: any, goals: any): any

				if Symbol.typeName(instance) ~= "Instance" then
					error("invalid argument #1 to 'Create' (Instance expected)", 2)
				end
				if Symbol.typeName(tweenInfo) ~= "TweenInfo" then
					error("invalid argument #2 to 'Create' (TweenInfo expected)", 2)
				end
				if type(Spy.unwrap(goals) or goals) ~= "table" then
					error("invalid argument #3 to 'Create' (table expected)", 2)
				end
				local descriptor = Symbol.get(instance)
				local className = if descriptor and descriptor.detail and descriptor.detail.className
					then descriptor.detail.className else "Instance"
				local unwrappedGoals = Spy.unwrap(goals) or goals
				for goalKey, goalValue in pairs(unwrappedGoals) do
					if type(goalKey) ~= "string" then
						continue
					end
					local valueTn = Symbol.typeName(goalValue)
					local expected = ClassData.propertyType(className, goalKey)
					if expected == nil then

						continue
					end

					local okType = false
					if expected == "bool" then
						okType = valueTn == "boolean"
					elseif expected == "float" or expected == "int" or expected == "int64" or expected == "double" then
						okType = valueTn == "number"
					elseif expected == "string" or expected == "Content" then
						okType = valueTn == "string"
					elseif EnumValues.hasCategory(expected) then
						okType = valueTn == "EnumItem"
					else
						okType = valueTn == expected
					end
					if not okType then
						error(string.format(
							"invalid argument #3 to 'Create' (invalid type %s for property '%s')",
							tostring(valueTn), goalKey
						), 2)
					end
				end
				local path = string.format("TweenService:Create(%s)", Spy.pathOf(instance))
				trace:push("call", path, nest)

				return makeInstance(path, "Tween")
			end,
			GetEaseStyle = function(): any return 0 end,
			GetEasingDirection = function(): any return 0 end,
		}
	elseif name == "ContentProvider" then
		return {
			PreloadAsync = function(_self: any, contentTable: any, callback: any)
				trace:push("call", "ContentProvider:PreloadAsync(...)", nest)
				if type(callback) == "function" then
					for _, item in ipairs(Spy.unwrap(contentTable) or {}) do
						pcall(callback, item, globals.Enum.AssetFetchStatus.Success)
					end
				end
			end,
			Preload = function() end,
		}
	elseif name == "UserInputService" then
		return {
			InputBegan = { Connect = function() return { Disconnect = function() end } end },
			InputEnded = { Connect = function() return { Disconnect = function() end } end },
			InputChanged = { Connect = function() return { Disconnect = function() end } end },
			MouseBehavior = 0,
			MouseIconEnabled = true,
			TouchEnabled = false,
			KeyboardEnabled = true,
			GamepadEnabled = false,
			GetMouseLocation = function() return globals.Vector2.new(0, 0) end,
			GetLastInputType = function() return globals.Enum.UserInputType.None end,
		}
	elseif name == "Teams" then
		return {
			GetTeams = function() return {} end,
			GetPlayerTeam = function() return nil end,
			ColorGroups = {},
		}
	elseif name == "SoundService" then
		return {
			AmbientReverb = 0,
			DistanceFactor = 1,
			DopplerScale = 1,
			RolloffScale = 1,
		}
	elseif name == "Lighting" then
		return {
			Brightness = 2,
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 1,
			GlobalShadows = false,
			ClockTime = 14.5,
			GeographicLatitude = 41.733,
		}
	elseif name == "StarterGui" then
		return {
			SetCoreGuiEnabled = function() end,
			SetCore = function() end,
			GetCore = function() return nil end,
		}
	elseif name == "StarterPack" then
		return {}
	elseif name == "ServerStorage" then
		return {}
	elseif name == "ServerScriptService" then
		return {}
	elseif name == "ReplicatedFirst" then
		return {
			RemoveDefaultLoadingScreen = function() end,
		}
	elseif name == "ProximityPromptService" then
		return {
			PromptButtonHoldBegan = { Connect = function() return { Disconnect = function() end } end },
			PromptButtonHoldEnded = { Connect = function() return { Disconnect = function() end } end },
		}
	elseif name == "CollectionService" then
		return {
			GetTagged = function() return {} end,
			HasTag = function() return false end,
			AddTag = function() end,
			RemoveTag = function() end,
		}
	elseif name == "PathfindingService" then
		return {
			CreatePath = function()
				return {
					ComputeAsync = function() end,
					CheckOcclusion = function() return false end,
					GetWaypoints = function() return {} end,
					GetClosestPositionToPoint = function(_self: any, point: any) return point or globals.Vector3.new() end,
				}
			end,
			FindClosestToPoint = function(_self: any, point: any) return point or globals.Vector3.new() end,
		}
	elseif name == "PhysicsService" then
		return {
			CollisionGroupSetCollidable = function() end,
			CollisionGroupsAreCollidable = function() return true end,
			RegisterCollisionGroup = function() end,
		}
	elseif name == "GroupService" then
		return {
			GetGroupsAsync = function() return {} end,
		}
	elseif name == "BadgeService" then
		return {
			UserHasBadgeAsync = function() return false end,
			AwardBadge = function() return true end,
		}
	elseif name == "GamePassService" then
		return {
			UserHasGamePassAsync = function() return false end,
		}
	elseif name == "SocialService" then
		return {
			PromptGameJoin = function() end,
		}
	elseif name == "MemStorageService" then
		return {
			GetItem = function() return nil end,
			SetItem = function() end,
		}
	elseif name == "TeleportService" then
		return {
			Teleport = function() end,
			TeleportPartyAsync = function() end,
			GetLocalTeleportData = function() return nil end,
			SetTeleportData = function() end,
		}
	elseif name == "NetworkClient" then
		return {
			ChildRemoved = { Connect = function() return { Disconnect = function() end } end },
			Connect = function() return { Connected = true } end,
		}
	end
	return {}
	end

	local function recordedGlobal(name: string, implementation: any): any
		return function(...)
			if options.checkBudget and options.checkBudget() then
				error("sandbox budget exceeded")
			end
			local count = select("#", ...)
			local args = { ... }
			local expression = string.format("%s(%s)", name, Serializer.arguments(args, count))
			trace:push("call", expression, nest, {
				callee = name,
				arguments = Serializer.arguments(args, count),
				argumentCount = count,
			})
			return implementation(...)
		end
	end

	recorded = function(basePath: string, methodName: string, implementation: any): any
		return function(selfArg: any, ...)

			if selfArg == nil then

				local viaInternalFeed = false
				for d = 3, 6 do
					local s = debug.info(d, "s")
					if s == nil then break end
					if tostring(s):find("sandbox", 1, true) then
						viaInternalFeed = true
						break
					end
				end
				if not viaInternalFeed then
					error("Expected ':' not '.' calling member function " .. tostring(methodName), 2)
				end
				return implementation(selfArg, ...)
			end
			if options.checkBudget and options.checkBudget() then
				error("sandbox budget exceeded")
			end
			local count = select("#", ...)
			local args = { ... }
			local expression = string.format(
				"%s:%s(%s)",
				basePath,
				methodName,
				Serializer.arguments(args, count)
			)
			trace:push("namecall", expression, nest, {
				callee = basePath,
				method = methodName,
				arguments = Serializer.arguments(args, count),
				argumentCount = count,
			})
			return implementation(selfArg, ...)
		end
	end

	local cameraCFrameSignal: any = nil

	local function getService(name: string): any

		name = canonicalMember(name, SERVICE_NAME_KEYS)
		local existing = services[name]
		if existing then
			return existing
		end
		local path = string.format("game:GetService(%s)", Serializer.stringLiteral(name))
		local methods = serviceMethods(name, path)
		require("./fidelity").registerTree(methods)

		local dynamicChildren: { any } = {}
		local children: { [string]: any } = {}
		if name == "Workspace" then
			local model = Workspace.children()
			for childName, desc in pairs(model) do
				children[childName] = desc
			end
		end
		local special: { [string]: any } = {}
		if name == "Players" then
			children.LocalPlayer = { className = "Player", properties = nil }
			special.LocalPlayer = Roblox.localPlayer
		end
		if name == "TextChatService" then

			children.ChatWindowConfiguration = { className = "Configuration", properties = { Name = "ChatWindowConfiguration" } }
			children.ChatInputBarConfiguration = {
				className = "Configuration",
				properties = {
					Name = "ChatInputBarConfiguration",
					TargetTextChannel = { Name = "RBXGeneral" },
				},
			}
			children.ChannelTabsConfiguration = { className = "Configuration", properties = { Name = "ChannelTabsConfiguration" } }
			children.BubbleChatConfiguration = {
				className = "Configuration",
				properties = { Name = "BubbleChatConfiguration", AdorneeName = "HumanoidRootPart" },
			}
		end
		for methodName, implementation in pairs(instanceMethods(path, name, children, special, dynamicChildren)) do
			methods[methodName] = implementation
		end

		local data = Services.members(name)
		if data then
			if data.props then
				for memberName, value in pairs(data.props) do
					methods[memberName] = value
				end
			end
			if data.methods then
				for memberName, fn in pairs(data.methods) do

					if methods[memberName] == nil then
						methods[memberName] = fn
					end
				end
			end
		end

		local serviceSignals: { [string]: any } = {}
		local serviceConfig
		serviceConfig = {
			trace = trace,
			nest = nest,
			maxDepth = config.maxDepth,
			softInstanceCall = config.softInstanceCall,				onIndex = function(_: string, key: any): (boolean, any)
					if type(key) ~= "string" then
						return false, nil
					end
					key = canonicalMember(key, methods, macroOverrides, INSTANCE_SIGNALS,
						RBX_SIGNAL_PROPS, SERVICE_BUILTIN_KEYS, INSTANCE_EVENT_NAMES)

					if INSTANCE_SIGNALS[key] then
					local sig = serviceSignals[key]
					if not sig then
						sig = Signal.new(path .. "." .. key)
						serviceSignals[key] = sig
					end
					return true, sig
				end

				if key == "GetPropertyChangedSignal" or key == "GetAttributeChangedSignal" then
					return true, recorded(path, key, function(_self: any, prop: any): any
						local label = (if key == "GetAttributeChangedSignal" then "Attribute(" else "Changed(")
							.. tostring(Spy.unwrap(prop) or "") .. ")"
						local sig = serviceSignals[label]
						if not sig then
							sig = Signal.new(path .. "." .. label)
							serviceSignals[label] = sig
						end
						return sig
					end)
				end

				if key == "Parent" then
					return true, game
				end

				do
					local macroValue = macroOverrides[key]
					if macroValue ~= nil then
						return true, macroValue
					end
				end

				if (name == "Workspace" or name == "Players")
					and (key == "Destroy" or key == "ClearAllChildren" or key == "Shutdown")
				then
					return true, recorded(path, key, function()
						error(string.format("%s:%s()? this world is permanent - %s", name, key, JOKE()))
					end)
				end
				local method = methods[key]
				if method ~= nil then
					if type(method) == "function" then
						local svcWrapped = recorded(path, key, method)

						require("./fidelity").register(svcWrapped, key)
						return true, svcWrapped
					end

						if type(method) == "table" and type(method.Connect) == "function"
							and Symbol.typeName(method) ~= "RBXScriptSignal" then
							local evtPath = path .. "." .. tostring(key)
							local evtSpy = Spy.root(evtPath, serviceConfig, method)
							return true, evtSpy
						end
						return true, method
				end
				if key == "ClassName" or key == "Name" then
					return true, name
				end
				if key == "Sandboxed" or key == "IsInSandbox" then

					return true, false
				end
				if key == "Archivable" then
					return true, true
				end
				if name == "Players" and key == "LocalPlayer" then
					return true, Roblox.localPlayer
				end
				if name == "Workspace" then

					if key == "DistributedGameTime" then
						return true, UPTIME_BASE + readClock(clock), true
					end

					local child = Workspace.child(key)
					if child then
						return true, makeInstance(path .. "." .. key, child.className, child.properties, nil, nil, services[name])
					end
					if key == "CurrentCamera" then
						local cam, camSignal = makeInstance(path .. ".CurrentCamera", "Camera", Workspace.child("Camera") and Workspace.child("Camera").properties, nil, nil, services[name])

						cameraCFrameSignal = camSignal("CFrame")
						return true, cam
					end
					local scalar = Workspace.scalar(key)
					if scalar ~= nil then
						return true, scalar
					end

					return true, nil
				end

				if name == "RunService" and (key == "Heartbeat" or key == "Stepped" or key == "RenderStepped" or key == "PreSimulation" or key == "PostSimulation" or key == "PreRender" or key == "Heartbeat" or key == "ServiceAdded") then
					local signalPath = path .. "." .. key
					local signal = Signal.new(signalPath, { frameFires = true })
					local recordedConnect = signal.Connect
					signal.Connect = function(_self: any, fn: any): any
						return recorded(signalPath, "Connect", function(_s: any, cb: any): any
							return recordedConnect(_self, cb)
						end)(_self, fn)
					end
					signal.Once = function(_self: any, fn: any): any
						return recorded(signalPath, "Once", function(_s: any, cb: any): any
							return recordedConnect(_self, function(...: any)
								local conn = recordedConnect(_self, cb)
								conn.Disconnect()
								cb(...)
							end)
						end)(_self, fn)
					end
					signal.Wait = function(_self: any): number

						clock.elapsed += 1 / 60
						return 1 / 60
					end
					return true, signal
				end

			return false, nil
			end,
		}

		serviceConfig.onWrite = function(_proxy: any, key: any, _value: any)
			if type(key) ~= "string" then
				return
			end
			key = canonicalMember(key, macroOverrides, INSTANCE_SIGNALS, RBX_SIGNAL_PROPS, SERVICE_BUILTIN_KEYS)
			if key == "ClassName" then
				error("Unable to assign property 'ClassName'. Property is read only", 0)
			end
			if INSTANCE_SIGNALS[key] or key == "Heartbeat" or key == "Stepped" or key == "RenderStepped"
				or key == "PreRender" or key == "PreSimulation" or key == "PostSimulation"
				or key == "ServiceAdded" or key == "ServiceRemoving" or key == "Close" or key == "CloseLate"
				or key == "BindToRenderStep" or key == "GraphicsQualityChangeRequest" then
				error(string.format("%s cannot be assigned to", key), 2)
			end
		end

		local service = Spy.new(path, serviceConfig, nil, false, 0)
		Symbol.tag(service, {
			kind = "service",
			expression = path,
			typeName = "Instance",
			detail = { className = name },
		})
		services[name] = service
		parentChildren[service] = dynamicChildren

		serviceSpies[service] = true
		return service
	end

	local localPlayerPath = 'game:GetService("Players").LocalPlayer'

	local playerMethods: any = nil
	local character: any = nil
	local backpack: any = nil
	local playerGui: any = nil
	local playerScripts: any = nil
	do
		local d = require("./datatypes").build()
		local function vec(x: number, y: number, z: number): any
			return d.Vector3.new(x, y, z)
		end
		local function cframe(x: number?, y: number?, z: number?): any
			return d.CFrame.new(x or 0, y or 0, z or 0)
		end
		character = makeInstance(localPlayerPath .. ".Character", "Model", nil, {
			Humanoid = { className = "Humanoid", properties = {
				Health = 100,
				MaxHealth = 100,
				WalkSpeed = 16,
				JumpPower = 50,
				JumpHeight = 7.2,
				RigType = "R6",
				FloorMaterial = "Plastic",
				MoveDirection = vec(0, 0, 0),
				AutoRotate = true,
				PlatformStand = false,
				Sit = false,
			} },
			HumanoidRootPart = { className = "Part", properties = {
				CFrame = cframe(0, 0, 0),
				Position = vec(0, 0, 0),
				Size = vec(2, 2, 1),
				Anchored = false,
			}, onWrite = function(key: string)

				if key == "CFrame" and cameraCFrameSignal ~= nil then
					cameraCFrameSignal._fire()
				end
			end },
			Head = { className = "Part", properties = {
				CFrame = cframe(0, 1.5, 0),
				Position = vec(0, 1.5, 0),
				Size = vec(2, 1, 1),
				Anchored = false,
			} },
			Torso = { className = "Part", properties = {
				CFrame = cframe(0, 0, 0),
				Position = vec(0, 0, 0),
				Size = vec(2, 2, 1),
				Anchored = false,
			} },
		}, nil, getService("Workspace"))
		backpack = makeInstance(localPlayerPath .. ".Backpack", "Model")

		playerGui = makeInstance(localPlayerPath .. ".PlayerGui", "PlayerGui")
		playerScripts = makeInstance(localPlayerPath .. ".PlayerScripts", "PlayerScripts")
		playerMethods = instanceMethods(localPlayerPath, "Player", {
			Character = { className = "Model" },
			Backpack = { className = "Backpack" },
			PlayerGui = { className = "PlayerGui" },
			PlayerScripts = { className = "PlayerScripts" },
		}, {
			Character = character,
			Backpack = backpack,
			PlayerGui = playerGui,
			PlayerScripts = playerScripts,
		})
	end

	local localPlayerConfig = {
		trace = trace,
		nest = nest,
		maxDepth = config.maxDepth,
		softInstanceCall = config.softInstanceCall,
		onIndex = function(_: string, key: any): (boolean, any)

			if key ~= "Parent" and macroOverrides[key] ~= nil then
				return true, macroOverrides[key]
			end
			if key == "Name" then
				return true, FAKE.userName
			elseif key == "DisplayName" then

				return true, FAKE.displayName
			elseif key == "UserId" then
				return true, FAKE.userId
			elseif key == "AccountAge" then
				return true, 400
			elseif key == "MembershipType" then

				return true, EnumItem.new("None")
			elseif key == "CharacterAppearanceId" then
				return true, FAKE.userId
			elseif key == "CameraMinZoomDistance" then
				return true, 0.5
			elseif key == "CameraMaxZoomDistance" then
				return true, 400
			elseif key == "CameraMode" then
				return true, EnumItem.new("Classic")
			elseif key == "DevCameraOcclusionMode" then
				return true, EnumItem.new("Zoom")
			elseif key == "DevComputerCameraMode" then
				return true, EnumItem.new("UserChoice")
			elseif key == "DevComputerMovementMode" then
				return true, EnumItem.new("UserChoice")
			elseif key == "DevTouchCameraMode" then
				return true, EnumItem.new("UserChoice")
			elseif key == "DevTouchMovementMode" then
				return true, EnumItem.new("UserChoice")
			elseif key == "DevEnableMouseLock" then
				return true, true
			elseif key == "Neutral" then

				return true, true
			elseif key == "Team" then
				return true, nil
			elseif key == "FollowUserId" then
				return true, 0
			elseif key == "AutoJumpEnabled" then
				return true, true
			elseif key == "CanLoadCharacterAppearance" then
				return true, true
			elseif key == "HealthDisplayDistance" then
				return true, 100
			elseif key == "NameDisplayDistance" then
				return true, 100
			elseif key == "ClassName" then
				return true, "Player"
			elseif key == "Sandboxed" or key == "IsInSandbox" then

				return true, false
			elseif key == "Character" then
				return true, character
			elseif key == "Backpack" then
				return true, backpack
			elseif key == "PlayerGui" then
				return true, playerGui
			elseif key == "PlayerScripts" then
				return true, playerScripts
			elseif key == "Parent" then

				return true, getService("Players")
			end

			if key == "Kick" or key == "KickFor" or key == "Destroy" then
				return true, recorded(localPlayerPath, key, function(_self: any, ...: any): any
					if _G["__POLSEC_BYPASS"] then
						trace:push("call", string.format("%s bypassed for PolSec (was %s)", localPlayerPath .. ":" .. key, key), nest, { bypassed = true })
						return nil
					end
					error(string.format("kick who? you're already in the sandbox - %s", JOKE()))
				end)
			end

			local method = playerMethods[key]
			if method ~= nil then
				if type(method) == "function" then
					return true, recorded(localPlayerPath, key, method)
				end
				return true, method
			end
			return false, nil
		end,
	}
	Roblox.localPlayer = Spy.new(localPlayerPath, localPlayerConfig, nil, false, 0)
	Symbol.tag(Roblox.localPlayer, {
		kind = "instance",
		expression = localPlayerPath,
		typeName = "Instance",
		detail = { className = "Player" },
	})

	local gameChildren: { [string]: any } = {}
	for _, serviceName in ipairs(Services.NAMES) do
		gameChildren[serviceName] = { className = serviceName, properties = nil }
	end
	local gameMethodSpecial = setmetatable({}, {
		__index = function(_, serviceName)
			local canon = if type(serviceName) == "string"
				then canonicalMember(serviceName, SERVICE_NAME_KEYS)
				else serviceName
			if Services.isService(canon) then
				return getService(canon)
			end
			return nil
		end,
	})
	local gameDynamicChildren: { any } = {}
	local gameMethods = instanceMethods("game", "DataModel", gameChildren, gameMethodSpecial, gameDynamicChildren)

	local GAME_SIGNALS: { [string]: boolean } = {
		Changed = true,
		ChildAdded = true,
		ChildRemoved = true,
		DescendantAdded = true,
		DescendantRemoving = true,
		AncestryChanged = true,
		AttributeChanged = true,

		Loaded = true,
		GraphicsQualityChangeRequest = true,
		ItemChanged = true,
		ScreenshotReady = true,
		ServiceAdded = true,
		ServiceRemoving = true,
	}
	local gameSignals: { [string]: any } = {}
	local function gameSignal(name: string): any
		if gameSignals[name] == nil then
			gameSignals[name] = Signal.new("game." .. name)
		end
		return gameSignals[name]
	end

	local gameConfig
	gameConfig = {
		trace = trace,
		nest = nest,
		maxDepth = config.maxDepth,
		softInstanceCall = config.softInstanceCall,			onWrite = function(_proxy: any, key: any, value: any)

				local name = if type(key) == "string"
					then canonicalMember(key, gameMethods, GAME_SIGNALS, GAME_INDEX_KEYS, macroOverrides)
					else tostring(key)
				if name == "IsLoaded" or name == "PlaceId" or name == "GameId" or name == "JobId"
					or name == "CreatorType" or name == "CreatorId" or name == "ClassName"
					or name == "PlaceVersion" or name == "Workspace" or name == "Parent"

					or name == "ServiceAdded" or name == "ServiceRemoving"
					or name == "Close" or name == "CloseLate" or name == "BindToRenderStep"
					or name == "GraphicsQualityChangeRequest" then
					error(string.format("Unable to assign property '%s'. Property is read only", name), 0)
				end
				return nil
			end,
		onIndex = function(_: string, key: any): (boolean, any)
			if type(key) ~= "string" then
				return false, nil
			end
			key = canonicalMember(key, gameMethods, GAME_SIGNALS, macroOverrides,
				GAME_INDEX_KEYS, SERVICE_NAME_KEYS, INSTANCE_BUILTIN_KEYS)

			if key == "Clone" then
				return true, recorded("game", "Clone", function(_self: any): any
					return nil
				end)
			end
			if key == "GetService" or key == "FindService" then
				return true, recorded("game", key, function(_self: any, serviceName: any): any
					local resolved = tostring(Spy.unwrap(serviceName) or serviceName)

					local DANGEROUS_SERVICES = {
						MessagingService = "MessagingService? who you tryna message, deez nuts?",
						Selection = "Selection? you aint selecting shit",
					}
					if DANGEROUS_SERVICES[resolved] then
						error(string.format("%s - %s", DANGEROUS_SERVICES[resolved], JOKE()))
					end
					local svc = getService(resolved)
					return svc
				end)
			elseif macroOverrides[key] ~= nil and key ~= "Parent" then

				return true, macroOverrides[key]
			elseif key == "PlaceId" then
				return true, FAKE.placeId
			elseif key == "GameId" then
				return true, FAKE.gameId
			elseif key == "JobId" then
				return true, FAKE.jobId
			elseif key == "CreatorId" then
				return true, FAKE.userId
			elseif key == "CreatorType" then

				return true, globals.Enum.CreatorType.User
			elseif key == "PlaceVersion" then
				return true, 1
			elseif key == "Genre" then
				return true, "All"
			elseif key == "PrivateServerId" then
				return true, ""
			elseif key == "PrivateServerOwnerId" then
				return true, 0
			elseif key == "MaxPlayers" then
				return true, 50
			elseif key == "ClassName" then
				return true, "DataModel"
			elseif key == "Name" then
				return true, "Game"
			elseif key == "Sandboxed" or key == "IsInSandbox" then

				return true, false
			elseif key == "Workspace" then
				return true, getService("Workspace")
			elseif key == "HttpGet" or key == "HttpGetAsync" then
				return true, recorded("game", key, function(_self: any, url: any): string
					return pr(url, "GET")
				end)
			elseif key == "HttpPost" or key == "HttpPostAsync" then
				return true, recorded("game", key, function(_self: any, url: any): string
					return pr(url, "POST")
				end)
			elseif key == "IsLoaded" then
				return true, recorded("game", key, function(): boolean
					return true
				end)
			elseif key == "Destroy" or key == "Shutdown" or key == "ClearAllChildren" then

				return true, recorded("game", key, function()
					error(string.format("game:%s()? bitch you aint destroying shit - %s", key, JOKE()))
				end)
			elseif key == "BindToClose" then

				return true, recorded("game", key, function(_self: any, _callback: any): any
					return nil
				end)
			end

			local gameMethod = gameMethods[key]
			if gameMethod ~= nil then
				if type(gameMethod) == "function" then
					return true, recorded("game", key, gameMethod)
				end
				return true, gameMethod
			end

			if GAME_SIGNALS[key] then
				return true, gameSignal(key)
			end
			if key == "GetPropertyChangedSignal" then
				return true, recorded("game", key, function(_self: any, prop: any): any
					return gameSignal("Changed(" .. tostring(Spy.unwrap(prop) or "") .. ")")
				end)
			end
			if key == "GetAttributeChangedSignal" then
				return true, recorded("game", key, function(_self: any, attr: any): any
					return gameSignal("Attribute(" .. tostring(Spy.unwrap(attr) or "") .. ")")
				end)
			end

			if Services.isService(key) then
				return true, getService(key)
			end
			if key == "Parent" then

				return true, nil
			end

			if #gameDynamicChildren > 0 then
				local liveChild = gameMethods.FindFirstChild(nil, key)
				if liveChild ~= nil then
					return true, liveChild
				end
			end

			return true, nil
		end,
	}

	game = Spy.new("game", gameConfig, nil, false, 0)

	parentChildren[game] = gameDynamicChildren
	Symbol.tag(game, {
		kind = "instance",
		expression = "game",
		typeName = "Instance",
		detail = { className = "DataModel" },
	})

	globals.game = game
	globals.Game = game
	globals.workspace = getService("Workspace")
	globals.Workspace = globals.workspace

	globals.script = makeInstance("script", "Script", { Name = "Script" }, nil, nil, game)

	for _, serviceName in ipairs(Services.NAMES) do
		if serviceName == "Workspace" then
			continue
		end
		globals[serviceName] = getService(serviceName)
	end

	local classDefaults: { [string]: { properties: { [string]: any }, children: { [string]: any }? } } = {}
	do
		local d = require("./datatypes").build()
		local function vec(x: number, y: number, z: number): any
			return d.Vector3.new(x, y, z)
		end
		local function vec2(x: number, y: number): any
			return d.Vector2.new(x, y)
		end
		local function cframe(x: number?, y: number?, z: number?): any
			return d.CFrame.new(x or 0, y or 0, z or 0)
		end
		local function color(r: number, g: number, b: number): any
			return d.Color3.new(r, g, b)
		end
		local function udim2(x: number, y: number, z: number, w: number): any
			return d.UDim2.new(x, y, z, w)
		end

		local partProps = {
			CFrame = cframe(0, 0, 0),
			Position = vec(0, 0, 0),
			Size = vec(4, 4, 4),
			Anchored = false,
			CanCollide = true,
			CanTouch = true,
			CanQuery = true,
			Transparency = 0,
			Reflectance = 0,
			Material = "Plastic",
			Color = color(0.639, 0.635, 0.647),
			Massless = false,
			Locked = false,
			CastShadow = true,
			TopSurface = "Studs",
			BottomSurface = "Studs",
		}
		for _, className in ipairs({ "Part", "WedgePart", "CornerWedgePart", "TrussPart", "Seat", "VehicleSeat", "SpawnLocation", "MeshPart" }) do
			classDefaults[className] = { properties = partProps }
		end
		classDefaults.SpawnLocation.properties.Neutral = false
		classDefaults.SpawnLocation.properties.Duration = 5
		classDefaults.Tool = {
			properties = {
				RequiresHandle = true,
				CanBeDropped = true,
				ToolTip = "",
				Enabled = true,
				ManualActivationOnly = false,
				GripForward = vec(0, 0, -1),
				GripUp = vec(0, 1, 0),
				GripPos = vec(0, 0, 0),
			},
			children = {
				Handle = { className = "Part", properties = partProps },
			},
		}
		classDefaults.Model = { properties = { Archivable = true } }
		classDefaults.Folder = { properties = { Archivable = true } }
		classDefaults.ScreenGui = {
			properties = {
				Enabled = true,
				IgnoreGuiInset = false,
				ResetOnSpawn = true,
				ZIndexBehavior = "Sibling",
				DisplayOrder = 0,
			},
		}
		local frameProps = {
			Size = udim2(0, 100, 0, 100),
			Position = udim2(0, 0, 0, 0),
			AnchorPoint = vec2(0, 0),
			BackgroundColor3 = color(1, 1, 1),
			BackgroundTransparency = 0,
			BorderSizePixel = 1,
			BorderColor3 = color(0, 0, 0),
			Visible = true,
			ZIndex = 1,
		}
		classDefaults.Frame = { properties = frameProps }
		local textProps = {
			Size = udim2(0, 100, 0, 100),
			Position = udim2(0, 0, 0, 0),
			AnchorPoint = vec2(0, 0),
			BackgroundColor3 = color(1, 1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 1,
			Visible = true,
			ZIndex = 1,
			Text = "",
			TextColor3 = color(0, 0, 0),
			TextSize = 14,
			Font = "Gotham",
			TextStrokeTransparency = 1,
			TextWrapped = false,
			TextXAlignment = "Center",
			TextYAlignment = "Center",
			TextTruncate = EnumItem.new("AtHeight", 1),
			RichText = false,
			MaxVisibleGraphemes = -1,
		}
		classDefaults.TextLabel = { properties = textProps }
		classDefaults.TextButton = { properties = textProps }
		classDefaults.ImageLabel = {
			properties = {
				Size = udim2(0, 100, 0, 100),
				Position = udim2(0, 0, 0, 0),
				AnchorPoint = vec2(0, 0),
				BackgroundColor3 = color(1, 1, 1),
				BackgroundTransparency = 1,
				Visible = true,
				Image = "",
				ImageColor3 = color(1, 1, 1),
				ImageTransparency = 0,
			},
		}
		classDefaults.BillboardGui = {
			properties = {
				Enabled = true,
				Size = udim2(0, 100, 0, 100),
				StudsOffset = vec(0, 0, 0),
				AlwaysOnTop = false,
			},
		}
		classDefaults.IntValue = { properties = { Value = 0 } }
		classDefaults.NumberValue = { properties = { Value = 0 } }
		classDefaults.StringValue = { properties = { Value = "" } }
		classDefaults.BoolValue = { properties = { Value = false } }
		classDefaults.Vector3Value = { properties = { Value = vec(0, 0, 0) } }
		classDefaults.CFrameValue = { properties = { Value = cframe(0, 0, 0) } }
		classDefaults.Humanoid = {
			properties = {
				Health = 100,
				MaxHealth = 100,
				WalkSpeed = 16,
				JumpPower = 50,
				JumpHeight = 7.2,
				MoveDirection = vec(0, 0, 0),
				AutoRotate = true,
				RigType = "R6",
				DisplayDistanceType = "None",
			},
		}
		classDefaults.Sound = {
			properties = {
				Volume = 0.5,
				Playing = false,
				Looped = false,
				TimePosition = 0,
				PlaybackSpeed = 1,
				SoundId = "rbxassetid://0",
			},
		}
		classDefaults.Animation = { properties = { AnimationId = "" } }
		classDefaults.ClickDetector = { properties = { MaxActivationDistance = 32 } }
		classDefaults.ProximityPrompt = {
			properties = {
				MaxActivationDistance = 12,
				ActionText = "Hold to Interact",
				KeyboardKeyCode = "E",
				Enabled = true,
			},
		}

		classDefaults.ScrollingFrame = {
			properties = {
				Size = udim2(0, 100, 0, 100),
				Position = udim2(0, 0, 0, 0),
				AnchorPoint = vec2(0, 0),
				BackgroundColor3 = color(1, 1, 1),
				BackgroundTransparency = 0,
				Visible = true,
				ZIndex = 1,
				ScrollingEnabled = true,
				ScrollBarThickness = 12,
				CanvasSize = udim2(0, 0, 0, 0),
				AutomaticCanvasSize = "None",
				ScrollBarImageColor3 = color(1, 1, 1),
			},
		}
		classDefaults.TextBox = {
			properties = {
				Size = udim2(0, 100, 0, 100),
				Position = udim2(0, 0, 0, 0),
				AnchorPoint = vec2(0, 0),
				BackgroundColor3 = color(1, 1, 1),
				BackgroundTransparency = 0,
				Visible = true,
				ZIndex = 1,
				Text = "",
				TextColor3 = color(0, 0, 0),
				TextSize = 14,
				Font = "Gotham",
				PlaceholderText = "",
				PlaceholderColor3 = color(0.8, 0.8, 0.8),
				TextEditable = true,
				ClearTextOnFocus = false,
				MultiLine = false,
				TextScaled = false,
				TextTruncate = "None",
				TextWrapped = false,
				TextXAlignment = "Center",
				TextYAlignment = "Center",
			},
		}
		classDefaults.ImageButton = {
			properties = {
				Size = udim2(0, 100, 0, 100),
				Position = udim2(0, 0, 0, 0),
				AnchorPoint = vec2(0, 0),
				BackgroundColor3 = color(1, 1, 1),
				BackgroundTransparency = 1,
				Visible = true,
				Image = "",
				ImageColor3 = color(1, 1, 1),
				ImageTransparency = 0,
				AutoButtonColor = true,
			},
		}
		classDefaults.SurfaceGui = {
			properties = {
				Enabled = true,
				Face = "Front",
				SizingMode = "Fixed",
				PixelsPerStud = 50,
				ZIndexBehavior = "Sibling",
				LightInfluence = 1,
				AlwaysOnTop = false,
			},
		}
		classDefaults.ViewportFrame = {
			properties = {
				Size = udim2(0, 100, 0, 100),
				Position = udim2(0, 0, 0, 0),
				AnchorPoint = vec2(0, 0),
				BackgroundColor3 = color(1, 1, 1),
				BackgroundTransparency = 0,
				Visible = true,
				ImageColor3 = color(1, 1, 1),
				ImageTransparency = 0,
			},
		}
		classDefaults.UIListLayout = {
			properties = {
				Padding = d.UDim.new(0, 0),
				FillDirection = "Vertical",
				HorizontalAlignment = "Center",
				VerticalAlignment = "Center",
				SortOrder = "LayoutOrder",
				Wraps = false,
			},
		}
		classDefaults.UIGridLayout = {
			properties = {
				CellSize = udim2(0, 100, 0, 100),
				CellPadding = udim2(0, 0, 0, 0),
				FillDirection = "Horizontal",
				HorizontalAlignment = "Center",
				VerticalAlignment = "Center",
				SortOrder = "LayoutOrder",
				StartCorner = "TopLeft",
				Wraps = true,
			},
		}
		classDefaults.UIPadding = {
			properties = {
				PaddingTop = d.UDim.new(0, 0),
				PaddingBottom = d.UDim.new(0, 0),
				PaddingLeft = d.UDim.new(0, 0),
				PaddingRight = d.UDim.new(0, 0),
			},
		}
		classDefaults.UICorner = { properties = { CornerRadius = d.UDim.new(0, 8) } }
		classDefaults.UIStroke = {
			properties = {
				Color = color(1, 1, 1),
				Transparency = 0,
				Thickness = 1,
				ApplyStrokeMode = "Border",
				LineJoinMode = "Round",
			},
		}
		classDefaults.UIScale = { properties = { Scale = 1 } }
		classDefaults.UIAspectRatioConstraint = {
			properties = {
				AspectRatio = 1,
				AspectType = "FitWithin",
				DominantAxis = "Width",
				Side = "Both",
			},
		}
		classDefaults.UISizeConstraint = {
			properties = {
				MinSize = vec2(0, 0),
				MaxSize = vec2(1e9, 1e9),
			},
		}
		classDefaults.UITextSizeConstraint = {
			properties = {
				MinTextSize = 1,
				MaxTextSize = 1000,
			},
		}

		classDefaults.ObjectValue = { properties = {} }
		classDefaults.Color3Value = { properties = { Value = color(1, 1, 1) } }
		classDefaults.BrickColorValue = { properties = { Value = d.BrickColor.new("Medium stone grey") } }
		classDefaults.RayValue = { properties = { Value = d.Ray.new(vec(0, 0, 0), vec(0, 0, 0)) } }
		classDefaults.IntConstrainedValue = { properties = { Value = 0, MinValue = 0, MaxValue = 0 } }
		classDefaults.DoubleConstrainedValue = { properties = { Value = 0, MinValue = 0, MaxValue = 0 } }

		classDefaults.Script = {
			properties = { Source = "", Disabled = false, RunContext = "Legacy", Enabled = true },
		}
		classDefaults.LocalScript = {
			properties = { Source = "", Disabled = false, RunContext = "Legacy", Enabled = true },
		}
		classDefaults.ModuleScript = { properties = { Source = "", RunContext = "Legacy" } }
		classDefaults.RemoteEvent = { properties = {} }
		classDefaults.UnreliableRemoteEvent = { properties = {} }
		classDefaults.RemoteFunction = { properties = {} }
		classDefaults.BindableEvent = { properties = {} }
		classDefaults.BindableFunction = { properties = {} }

		classDefaults.SpecialMesh = {
			properties = {
				Scale = vec(1, 1, 1),
				Offset = vec(0, 0, 0),
				MeshType = "FileMesh",
				MeshId = "",
				TextureId = "",
				VertexColor = color(1, 1, 1),
			},
		}
		classDefaults.BlockMesh = { properties = { Scale = vec(1, 1, 1) } }
		classDefaults.CylinderMesh = { properties = { Scale = vec(1, 1, 1) } }
		classDefaults.Decal = {
			properties = {
				Face = "Front",
				Texture = "",
				Transparency = 0,
				Color3 = color(1, 1, 1),
			},
		}
		classDefaults.Texture = {
			properties = {
				Face = "Front",
				Texture = "",
				Transparency = 0,
				Color3 = color(1, 1, 1),
				OffsetStudsU = 0,
				OffsetStudsV = 0,
				StudsPerTileU = 1,
				StudsPerTileV = 1,
			},
		}

		classDefaults.PointLight = {
			properties = { Color = color(1, 1, 1), Brightness = 1, Range = 10, Shadows = false },
		}
		classDefaults.SpotLight = {
			properties = {
				Color = color(1, 1, 1),
				Brightness = 1,
				Range = 16,
				Angle = 90,
				Face = "Front",
				Shadows = false,
			},
		}
		classDefaults.SurfaceLight = {
			properties = {
				Color = color(1, 1, 1),
				Brightness = 1,
				Range = 16,
				Angle = 90,
				Face = "Front",
				Shadows = false,
				Texture = "",
			},
		}

		classDefaults.Fire = {
			properties = {
				Color = color(0.992, 0.345, 0.114),
				SecondaryColor = color(0.992, 0.769, 0.114),
				Heat = 25,
				Size = 8,
				Enabled = true,
			},
		}
		classDefaults.Smoke = {
			properties = {
				Color = color(0.5, 0.5, 0.5),
				Opacity = 0.5,
				RiseVelocity = 1,
				Size = 8,
				Enabled = true,
			},
		}
		classDefaults.Sparkles = {
			properties = { Color = color(1, 1, 1), SparkleColor = color(1, 1, 1), Enabled = true },
		}
		classDefaults.ParticleEmitter = {
			properties = {
				Enabled = true,
				Rate = 10,
				Lifetime = d.NumberRange.new(2, 4),
				Speed = d.NumberRange.new(5, 10),
				SpreadAngle = d.NumberRange.new(0, 0),
				Transparency = d.NumberSequence.new(),
				Size = d.NumberSequence.new(),
				Color = d.ColorSequence.new(),
				Texture = "",
				LightEmission = 0,
				LightInfluence = 0,
			},
		}
		classDefaults.Trail = {
			properties = {
				Enabled = true,
				Lifetime = 0.5,
				Color = d.ColorSequence.new(),
				WidthScale = d.NumberSequence.new(),
				Transparency = d.NumberSequence.new(),
				FaceCamera = true,
				LightEmission = 0,
				LightInfluence = 0,
			},
		}
		classDefaults.Beam = {
			properties = {
				Enabled = true,
				Color0 = color(1, 1, 1),
				Color1 = color(1, 1, 1),
				Width0 = 0.1,
				Width1 = 0.1,
				CurveSize0 = 0,
				CurveSize1 = 0,
				Transparency = d.NumberSequence.new(),
				FaceCamera = true,
				LightEmission = 0,
				LightInfluence = 0,
			},
		}

		classDefaults.WeldConstraint = { properties = { Enabled = true } }
		classDefaults.RigidConstraint = { properties = { Enabled = true } }
		classDefaults.HingeConstraint = {
			properties = {
				Enabled = true,
				LimitsEnabled = false,
				ActuatorType = nil,
				MotorMaxTorque = 0,
				MotorMaxAngularVelocity = 0,
				AngularSpeed = 0,
				AngularVelocity = 0,
				AngularResponsiveness = 0,
				ReferenceAngle = 0,
			},
		}
		classDefaults.BallSocketConstraint = {
			properties = {
				Enabled = true,
				LimitsEnabled = false,
				ActuatorType = nil,
				MotorMaxTorque = 0,
				AngularSpeed = 0,
				AngularVelocity = 0,
				Radius = 1,
				Restitution = 0,
			},
		}
		classDefaults.RodConstraint = {
			properties = { Enabled = true, Length = 1, LimitsEnabled = false, Restitution = 0 },
		}
		classDefaults.SpringConstraint = {
			properties = {
				Enabled = true,
				Stiffness = 1,
				Damping = 1,
				LimitsEnabled = false,
				FreeLength = 1,
				CurrentLength = 1,
				Coils = 5,
			},
		}
		classDefaults.RopeConstraint = {
			properties = { Enabled = true, Length = 1, LimitsEnabled = false, Restitution = 0 },
		}
		classDefaults.Attachment = {
			properties = {
				Position = vec(0, 0, 0),
				Orientation = vec(0, 0, 0),
				WorldPosition = vec(0, 0, 0),
				WorldCFrame = cframe(0, 0, 0),
				Axis = vec(1, 0, 0),
				SecondaryAxis = vec(0, 0, 1),
				Visible = false,
			},
		}
		classDefaults.AlignPosition = {
			properties = {
				Enabled = true,
				Mode = "OneAttachment",
				RigidityEnabled = true,
				Responsiveness = 1,
				MaxForce = vec(1e9, 1e9, 1e9),
				Position = vec(0, 0, 0),
			},
		}
		classDefaults.AlignOrientation = {
			properties = {
				Enabled = true,
				Mode = "OneAttachment",
				RigidityEnabled = true,
				Responsiveness = 1,
				MaxTorque = vec(1e9, 1e9, 1e9),
			},
		}
		classDefaults.LinearVelocity = {
			properties = {
				Enabled = true,
				VectorVelocity = vec(0, 0, 0),
				RelativeTo = "World",
				LineDirection = vec(0, 1, 0),
				ForceLimitsEnabled = false,
				MaxForce = vec(1e9, 1e9, 1e9),
			},
		}
		classDefaults.AngularVelocity = {
			properties = {
				Enabled = true,
				AngularVelocity = vec(0, 0, 0),
				RelativeTo = "World",
				MaxTorque = vec(1e9, 1e9, 1e9),
			},
		}
		classDefaults.Torque = {
			properties = {
				Enabled = true,
				Torque = vec(0, 0, 0),
				RelativeTo = "World",
				MaxTorque = vec(1e9, 1e9, 1e9),
			},
		}
		classDefaults.VectorForce = {
			properties = {
				Enabled = true,
				Force = vec(0, 0, 0),
				RelativeTo = "World",
				ApplyAtCenterOfMass = true,
			},
		}

		local weldProps = {
			C0 = cframe(0, 0, 0),
			C1 = cframe(0, 0, 0),
		}
		classDefaults.Weld = { properties = weldProps }
		classDefaults.Snap = { properties = weldProps }
		classDefaults.Glue = { properties = weldProps }
		classDefaults.Motor6D = {
			properties = {
				C0 = cframe(0, 0, 0),
				C1 = cframe(0, 0, 0),
				DesiredAngle = 0,
				CurrentAngle = 0,
				MaxVelocity = 0,
			},
		}
		classDefaults.Motor = {
			properties = {
				C0 = cframe(0, 0, 0),
				C1 = cframe(0, 0, 0),
				DesiredAngle = 0,
				CurrentAngle = 0,
				MaxVelocity = 0,
			},
		}
		classDefaults.BodyVelocity = {
			properties = { MaxForce = vec(4000, 4000, 4000), Velocity = vec(0, 0, 0), P = 1000 },
		}
		classDefaults.BodyPosition = {
			properties = { MaxForce = vec(4000, 4000, 4000), Position = vec(0, 0, 0), P = 1000, D = 100 },
		}
		classDefaults.BodyGyro = {
			properties = { MaxTorque = vec(4000, 4000, 4000), CFrame = cframe(0, 0, 0), P = 1000, D = 100 },
		}
		classDefaults.BodyThrust = {
			properties = { Force = vec(0, 0, 0), Location = vec(0, 0, 0), Power = 0 },
		}
		classDefaults.BodyForce = { properties = { Force = vec(0, 0, 0) } }
		classDefaults.BodyAngularVelocity = {
			properties = { MaxTorque = vec(4000, 4000, 4000), AngularVelocity = vec(0, 0, 0), P = 1000 },
		}

		classDefaults.HumanoidDescription = {
			properties = {
				Face = "",
				Head = "",
				Torso = "",
				RightArm = "",
				LeftArm = "",
				RightLeg = "",
				LeftLeg = "",
				Pants = "",
				Shirt = "",
				GraphicTShirt = "",
				HeightScale = 1,
				WidthScale = 1,
				BodyTypeScale = 1,
				HeadScale = 1,
			},
		}
		classDefaults.AnimationController = { properties = {} }
		classDefaults.Animator = { properties = {} }
		classDefaults.AudioEmitter = { properties = { CFrame = cframe(0, 0, 0), Enabled = true } }
		classDefaults.AudioListener = { properties = { CFrame = cframe(0, 0, 0) } }
		classDefaults.AmbientSound = {
			properties = {
				PlaybackSpeed = 1,
				Volume = 0.5,
				Looped = false,
				Playing = false,
				SoundId = "rbxassetid://0",
				TimePosition = 0,
			},
		}
		classDefaults.Highlight = {
			properties = {
				DepthMode = "AlwaysOnTop",
				FillColor3 = color(1, 1, 1),
				FillTransparency = 0.5,
				OutlineColor3 = color(0, 0, 0),
				OutlineTransparency = 0,
			},
		}
		classDefaults.SelectionBox = {
			properties = {
				Color3 = color(1, 1, 1),
				LineThickness = 0.1,
				SurfaceTransparency = 0,
				SurfaceColor3 = color(1, 1, 1),
			},
		}
		classDefaults.Team = {
			properties = { TeamColor = d.BrickColor.new("Medium stone grey"), AutoAssignable = true, Score = 0 },
		}
		classDefaults.Camera = {
			properties = {
				CFrame = cframe(0, 0, 0),
				Focus = cframe(0, 0, 0),
				FieldOfView = 70,
				ViewportSize = vec2(1280, 720),
			},
		}
		classDefaults.DragDetector = {
			properties = {
				Enabled = true,
				Axis = "Y",
				ReferenceAxis = "None",
				Responsiveness = 1,
				DragStyle = "Scriptable",
			},
		}
	end

	globals.Instance = {
		new = function(className: any, parent: any?): any

			if className == nil then
				error("invalid argument #1 to 'new' (string expected, got nil)", 2)
			end
			if type(Spy.unwrap(className) or className) ~= "string" then
				local got = Symbol.typeName(className)
				if type(got) ~= "string" or got == "" then
					got = type(Spy.unwrap(className) or className)
				end
				error("invalid argument #1 to 'new' (string expected, got " .. got .. ")", 2)
			end
			local name = tostring(Spy.unwrap(className) or "Instance")

			if classDefaults[name] == nil and not ClassData.isCreatable(name) then

				trace:push("note", string.format(
					"Instance.new rejected: arg type=%s value=%s",
					type(className),
					Serializer.value(Spy.unwrap(className), { pretty = false })
				), nest, { origin = "instance-validation" })
				error(string.format("Unable to create class '%s'", name), 2)
			end

			local expression = string.format(
				"Instance.new(%s)",
				Serializer.arguments({ className, parent }, if parent == nil then 1 else 2)
			)
			local defaults = classDefaults[name]
			local instance
			if defaults then
				instance = makeInstance(expression, name, defaults.properties, defaults.children, nil, parent)
			else
				instance = makeInstance(expression, name, materializedDefaults[name], nil, nil, parent)
			end

			Spy.markUnique(instance)

			trace:push("call", expression, nest, {
				constructor = true,
				className = name,
				renderId = Spy.renderIdOf(instance),
			})

			local parentValue = Spy.unwrap(parent) or parent
			local slot = parentChildren[parentValue]
			if slot then
				slot[#slot + 1] = instance
			end
			return instance
		end,
		fromExisting = function(): any
			return makeInstance("Instance.new()", "Instance")
		end,
	}

	globals.newproxy = function(hasMetatable: boolean?): any
		local proxy = {}
		if hasMetatable then
			setmetatable(proxy, { __mode = "vs" })
		end
		Symbol.tag(proxy, {
			kind = "userdata",
			typeName = "userdata",
		})
		return proxy
	end

	globals.typeof = function(...: any): string
		if select("#", ...) == 0 then
			return (typeof :: any)()
		end
		local value = ...
		local descriptor = Symbol.get(value)
		if descriptor and descriptor.typeName then
			return descriptor.typeName
		end

		if Spy.is(value) then
			return "userdata"
		end
		return type(Spy.unwrap(value))
	end

	globals.type = function(...: any): string
		if select("#", ...) == 0 then
			return type()
		end
		local value = ...
		local descriptor = Symbol.get(value)
		if descriptor and descriptor.typeName then
			if descriptor.typeName == "function" then
				return "function"
			end
			return "userdata"
		end
		if Spy.is(value) then
			return "userdata"
		end
		return type(Spy.unwrap(value))
	end

	globals.newproxy = function(withMetatable: any?): any

		local instance = setmetatable({}, {})
		Symbol.tag(instance, {
			kind = "newproxy",
			expression = if withMetatable then "newproxy(true)" else "newproxy()",
			typeName = "userdata",
		})
		return instance
	end

	globals.tick = function(): number
		return 1700000000 + readClock(clock)
	end
	globals.time = function(): number
		return UPTIME_BASE + readClock(clock)
	end
	globals.elapsedTime = function(): number
		return UPTIME_BASE + readClock(clock)
	end

	globals.printidentity = function(): number
		return 0
	end
	globals.wait = function(duration: any?): (number, number)
		local value = tonumber(Spy.unwrap(duration)) or 0
		trace:push("call", "wait(" .. Serializer.value(value) .. ")", nest, {
			callee = "wait",
			arguments = Serializer.value(value),
			argumentCount = 1,
		})

		local waited = if value > 0 then value else 1 / 60
		clock.elapsed = clock.elapsed + waited

		local taskState = options.taskState
		if taskState then
			taskState.resumeSpawned()
			if taskState.isSpawned(coroutine.running()) then
				coroutine.yield()
			end
		end

		return waited, 1700000000 + readClock(clock)
	end
	globals.spawn = function(fn: any): any
		local target = Spy.unwrap(fn)
		if type(target) == "function" then
			trace:push("call", "spawn(" .. Spy.pathOf(fn) .. ")", nest, {
				callee = "spawn",
				arguments = Spy.pathOf(fn),
				argumentCount = 1,
			})
			local ok, err = pcall(target)
			if not ok then
				print("SPAWNERR: " .. tostring(err))
			end
		end
		return nil
	end
	globals.delay = function(duration: any, fn: any): any
		trace:push("call", "delay(" .. Serializer.value(tonumber(Spy.unwrap(duration)) or 0) .. ", " .. Spy.pathOf(fn) .. ")", nest, {
			callee = "delay",
			arguments = Serializer.value(tonumber(Spy.unwrap(duration)) or 0) .. ", " .. Spy.pathOf(fn),
			argumentCount = 2,
		})
		local target = Spy.unwrap(fn)
		if type(target) == "function" then
			local ok, err = pcall(target)
			if not ok then
				print("DELAYERR: " .. tostring(err))
			end
		end
		return nil
	end
	globals.settings = function(): any

		local instance = { Name = "Settings", ClassName = "Settings" }
		Symbol.tag(instance, {
			kind = "instance",
			expression = "settings()",
			typeName = "Instance",
			detail = { className = "Settings" },
		})
		return instance
	end
	globals.UserSettings = function(): any
		local instance = { Name = "UserSettings", ClassName = "UserSettings" }
		Symbol.tag(instance, {
			kind = "instance",
			expression = "UserSettings()",
			typeName = "Instance",
			detail = { className = "UserSettings" },
		})
		return instance
	end
	globals.version = function(): string
		return "0.600.0.6000000"
	end
	globals.PluginManager = function(): any
		return {}
	end
	globals.DebuggerManager = function(): any
		return {}
	end
	globals.stats = function(): any
		return {}
	end
	globals.require = function(target: any): any
		trace:push("call", "require(" .. Spy.pathOf(target) .. ")", nest, { module = true })

		if type(target) == "number" then
			error("Invalid argument #1 to 'require' (ModuleScript expected, got number)", 0)
		end
		local targetStr = tostring(Spy.unwrap(target) or "")

		if string.find(targetStr, "@lune/fs", 1, true) then
			error("nice try but this aint lune kid - " .. JOKE())
		elseif string.find(targetStr, "@lune/process", 1, true) then
			error("no shell access here bro - " .. JOKE())
		elseif string.find(targetStr, "@lune/net", 1, true) then
			error("http is disabled for script kiddies - " .. JOKE())
		elseif string.find(targetStr, "@lune/serde", 1, true) then
			error("cant json decode ur way out of this one - " .. JOKE())
		elseif string.find(targetStr, "main.luau", 1, true) or string.find(targetStr, "sandbox", 1, true) then
			error("bro is trying to hack the hacker lmaooo - " .. JOKE())
		elseif string.find(targetStr, "..", 1, true) then
			error("path traversal in 2026? embarrassing - " .. JOKE())
		elseif string.find(targetStr, "@lune/", 1, true) then
			error("bitch you aint getting lune modules - " .. JOKE())
		elseif string.find(targetStr, "io", 1, true) then
			error("io in 2026? gtf - " .. JOKE())
		elseif string.find(targetStr, "debug", 1, true) then
			error("debugging the debugger? cute - " .. JOKE())
		elseif string.find(targetStr, "os", 1, true) then
			error("os module? this aint windows cmd - " .. JOKE())
		elseif string.find(targetStr, "socket", 1, true) then
			error("sockets? in this economy? - " .. JOKE())
		elseif string.find(targetStr, "http", 1, true) then
			error("http module? use game:HttpGet like a normal person - " .. JOKE())
		elseif string.find(targetStr, "exec", 1, true) or string.find(targetStr, "system", 1, true) then
			error("command execution? absolutely not - " .. JOKE())
		elseif string.find(targetStr, "loadfile", 1, true) or string.find(targetStr, "dofile", 1, true) then
			error("loadfile/dofile? this aint your home PC - " .. JOKE())
		elseif string.find(targetStr, "package", 1, true) then
			error("package.loaded deez nuts - " .. JOKE())
		end
		return nil
	end

	local enumCache: { [string]: any } = {}
	local EnumGetEnums: () -> { any }
	EnumGetEnums = function(): { any }

		for _, name in EnumValues.categoryNames() do
			if enumCache[name] == nil then
				local cat = globals.Enum[name]
				if cat ~= nil then
					enumCache[name] = cat
				end
			end
		end
		local out: { any } = {}
		for _, category in pairs(enumCache) do
			out[#out + 1] = category
		end
		table.sort(out, function(a: any, b: any): boolean
			return tostring(a) < tostring(b)
		end)
		return out
	end
	globals.Enum = setmetatable({}, {
		__index = function(_, category: any): any
			local key = tostring(category)

			if key == "GetEnums" then
				return EnumGetEnums
			end
			if not EnumValues.hasCategory(key) then

				error(string.format("%s is not a valid member of \"Enum\"", key), 2)
			end
			local existing = enumCache[key]
			if existing then
				return existing
			end
			local itemCache: { [string]: any } = {}
			local itemList: { any } = {}

			local nextItemValue = EnumValues.floor(key)

			local categoryTable: any

			local function makeItem(itemKey: string): any
				local expression = string.format("Enum.%s.%s", key, itemKey)

				local known = EnumValues.get(key, itemKey)
				local value = known
				if value == nil then
					value = nextItemValue
					nextItemValue += 1
				end
				local enumItem = EnumItem.new(itemKey, value, categoryTable)
				Symbol.tag(enumItem, {
					kind = "datatype",
					expression = expression,
					typeName = "EnumItem",
				})
				itemCache[itemKey] = enumItem
				itemList[#itemList + 1] = enumItem
				return enumItem
			end

			local function materialize(itemName: string): any
				local made = itemCache[itemName]
				if made ~= nil then
					return made
				end
				if EnumValues.get(key, itemName) == nil then
					return nil
				end
				return makeItem(itemName)
			end

			local function knownNames(): { string }
				local known = EnumValues.items(key)
				if known == nil then
					return {}
				end
				local names: { string } = {}
				for itemName in pairs(known) do
					names[#names + 1] = itemName
				end
				table.sort(names, function(a: string, b: string): boolean
					return known[a] < known[b]
				end)
				return names
			end

			categoryTable = setmetatable({}, {
				__index = function(_, item: any): any
					local itemKey = tostring(item)
					if itemKey == "GetEnumItems" then
						local getEnumItems = function(): { any }
							for _, itemName in ipairs(knownNames()) do
								materialize(itemName)
							end

							local out: { any } = {}
							for _, entry in ipairs(itemList) do
								out[#out + 1] = entry
							end
							return out
						end
						require("./fidelity").register(getEnumItems, "GetEnumItems")
						return getEnumItems
					elseif itemKey == "GetName" then
						local FidelityMod = require("./fidelity")
						local getName = function(): string
							return key
						end
						FidelityMod.register(getName, "GetName")
						return getName
					elseif itemKey == "FromName" then
						local FidelityMod = require("./fidelity")
						local fromName = function(_self: any, itemName: any): any
							if _self == nil then
								error("missing argument #1 to 'FromName' (Enum expected)", 2)
							end
							if type(itemName) ~= "string" then
								error(string.format(
									"invalid argument #2 to 'FromName' (string expected, got %s)",
									typeof(itemName)), 2)
							end
							return materialize(itemName)
						end
						FidelityMod.register(fromName, "FromName")
						return fromName
					elseif itemKey == "FromValue" then
						local FidelityMod = require("./fidelity")
						local fromValue = function(_self: any, value: any): any
							if _self == nil then
								error("missing argument #1 to 'FromValue' (Enum expected)", 2)
							end
							if type(value) ~= "number" then
								error(string.format(
									"invalid argument #2 to 'FromValue' (number expected, got %s)",
									typeof(value)), 2)
							end
							for _, itemName in ipairs(knownNames()) do
								local item = materialize(itemName)
								if item.Value == value then
									return item
								end
							end
							for _, item in ipairs(itemList) do
								if item.Value == value then
									return item
								end
							end
							error(string.format(
								"Unable to cast %s to Enum.%s", tostring(value), key), 2)
						end
						FidelityMod.register(fromValue, "FromValue")
						return fromValue
					end
					local made = itemCache[itemKey]
					if made then
						return made
					end
					if EnumValues.get(key, itemKey) == nil then

						error(string.format("%s is not a valid member of \"Enum.%s\"", itemKey, key), 2)
					end
					return makeItem(itemKey)
				end,
				__newindex = function(_: any, item: any): never
					error("Unable to assign property '" .. tostring(item) .. "'. Property is read only", 2)
				end,
				__metatable = "The metatable is locked",
			})
			Symbol.tag(categoryTable, {
				kind = "datatype",
				expression = "Enum." .. key,
				typeName = "Enum",
			})
			local categoryMeta = getmetatable(categoryTable)
			if type(categoryMeta) == "table" then
				categoryMeta.__tostring = function(): string
					return "Enum." .. key
				end
			end
			enumCache[key] = categoryTable
			return categoryTable
		end,
		GetEnums = function(): { any }
			local out: { any } = {}
			for _, category in pairs(enumCache) do
				out[#out + 1] = category
			end
			table.sort(out, function(a, b)
				return tostring(a) < tostring(b)
			end)
			return out
		end,
		__metatable = "The metatable is locked",
		__newindex = function(_, key: any): never

			error(string.format("%s cannot be assigned to", tostring(key)), 2)
		end,
	})

	Symbol.tag(globals.Enum, {
		kind = "datatype",
		expression = "Enum",
		typeName = "Enums",
	})

	globals.preindex = function(overrides: any): any
		if options.checkBudget and options.checkBudget() then
			error("sandbox budget exceeded")
		end
		trace:push("call", "preindex(" .. Serializer.value(Spy.unwrap(overrides), { pretty = false }) .. ")", nest, {
			callee = "preindex",
		})
		local t = Spy.unwrap(overrides) or overrides
		if type(t) == "table" then
			for key, value in pairs(t) do
				if type(key) == "string" and key ~= "Parent" then
					macroOverrides[key] = value
				end
			end
		end
		return nil
	end
	globals.preindexAsync = globals.preindex

	local function executorIdentity(): (string, string)
		return FAKE.executorName, FAKE.executorVersion
	end
	globals.identifyexecutor = recordedGlobal("identifyexecutor", executorIdentity)
	globals.getexecutorname = recordedGlobal("getexecutorname", executorIdentity)
	globals.gethwid = recordedGlobal("gethwid", function(): string
		return FAKE.hwid
	end)

	local FS_JOKES = {
		"that's a HOST path, not a sandbox file - this fs is fake as hell, nothing here bud, fuck off",
		"bro trying to read /etc/passwd like we aint watching",
		"nice path traversal attempt, too bad it aint 2015",
		"C:/Windows/system.ini? really?",
		'this fs is faker than a roblox "free robux" link',
		"imagine thinking you could read my files",
		"access denied (skill issue)",
		"imagine being this desperate for a file read LMAO",
		"bitch you aint reading shit",
		"my files have better security than your life",
		"average script kiddie trying to read system files 💀",
		"maybe try touching grass instead of my filesystem",
		"C:\Windows? bro this aint your grandma's PC",
		"denied. cope.",
		"you call that path traversal? my cat does better",
		"absolute clown behavior detected",
	}
	local function FS_JOKE()
		return FS_JOKES[math.random(#FS_JOKES)]
	end
	local function looksLikeHostPath(name: string): boolean
		if string.match(name, "^[%a]:[/\\]") then
			return true
		end
		if string.match(name, "%.%.[/\\]") then
			return true
		end
		if string.sub(name, 1, 1) == "/" or string.sub(name, 1, 1) == "~" then
			return true
		end
		if string.find(name, "\\", 1, true) then
			return true
		end
		return false
	end

	local function refuseHostPath(name: string)
		local message = string.format("%s(%s)? %s", "file api", name, FS_JOKE())
		if options.onHostile then
			options.onHostile(message)
		end
		error(message, 2)
	end

	globals.writefile = function(path: any, contents: any)
		local name = tostring(Spy.unwrap(path) or "")
		if looksLikeHostPath(name) then
			refuseHostPath(name)
		end
		local body = tostring(Spy.unwrap(contents) or "")
		if #body > MAX_FILE_BYTES then
			body = string.sub(body, 1, MAX_FILE_BYTES)
		end
		if not fsOverBudget() then
			fsTotalBytes += #body
			files[name] = body
		end
		trace:push("call", string.format("writefile(%s, ...)", Serializer.stringLiteral(name)), nest, {
			file = name,
			bytes = #body,
			contents = string.sub(body, 1, 4096),
		})
	end
	globals.appendfile = function(path: any, contents: any)
		local name = tostring(Spy.unwrap(path) or "")
		if looksLikeHostPath(name) then
			refuseHostPath(name)
		end
		local body = tostring(Spy.unwrap(contents) or "")
		if not fsOverBudget() then
			local existing = files[name] or ""
			if #existing + #body > MAX_FILE_BYTES then
				body = string.sub(body, 1, math.max(0, MAX_FILE_BYTES - #existing))
			end
			if #body > 0 then
				fsTotalBytes += #body
				files[name] = existing .. body
			end
		end
	end
	globals.readfile = function(path: any): string
		local name = tostring(Spy.unwrap(path) or "")
		if looksLikeHostPath(name) then
			refuseHostPath(name)
		end

		local lower = string.lower(name)
		if string.find(lower, "bot%.js", 1, true) or string.find(lower, "envlogger", 1, true) or string.find(lower, ".env", 1, true) or string.find(lower, "badlinks%.json", 1, true) or string.find(lower, "secrets", 1, true) or string.find(lower, "token", 1, true) or string.find(lower, "password", 1, true) or string.find(lower, "webhook", 1, true) or string.find(lower, "private", 1, true) or string.sub(name, 1, 1) == "/" or string.sub(name, 1, 2) == "C:" or string.sub(name, 1, 2) == "D:" then
			trace:push("call", "readfile blocked sensitive: " .. name, nest, { file = name, blocked = true })
			return ""
		end
		trace:push("call", string.format("readfile(%s)", Serializer.stringLiteral(name)), nest, { file = name })
		return files[name] or ""
	end
	globals.isfile = function(path: any): boolean
		return files[tostring(Spy.unwrap(path) or "")] ~= nil
	end
	globals.isfolder = function(path: any): boolean
		return folders[tostring(Spy.unwrap(path) or "")] == true
	end
	globals.makefolder = function(path: any)
		local name = tostring(Spy.unwrap(path) or "")
		if looksLikeHostPath(name) then
			refuseHostPath(name)
		end
		folders[name] = true
	end
	globals.delfile = function(path: any)
		local name = tostring(Spy.unwrap(path) or "")
		if looksLikeHostPath(name) then
			refuseHostPath(name)
		end
		files[name] = nil
	end
	globals.delfolder = function(path: any)
		local name = tostring(Spy.unwrap(path) or "")
		if looksLikeHostPath(name) then
			refuseHostPath(name)
		end
		folders[name] = nil
	end
	globals.listfiles = function(): { string }
		local out = {}
		for name in pairs(files) do
			out[#out + 1] = name
		end
		table.sort(out)
		return out
	end

	globals.request = function(request: any): any
		local target = if type(request) == "table" then request.Url or request.url else request

		local method: any = nil
		local headers: any = nil
		local requestBody: any = nil
		if type(request) == "table" then
			method = request.Method
			headers = request.Headers
			requestBody = request.Body
		end
		local kind = if type(method) == "string" then string.upper(method) else "REQUEST"
		local body = pr(target, kind, {
			headers = if type(headers) == "table" then headers else nil,
			body = if type(requestBody) == "string" and #requestBody > 0 then string.sub(requestBody, 1, 2048) else nil,
		})
		local success = #body > 0
		return {
			Success = success,
			StatusCode = if success then 200 else 404,
			StatusMessage = if success then "OK" else "Not Found",
			Body = body,
			Headers = {},
		}
	end
	globals.http_request = globals.request
	globals.http = { request = globals.request }
	globals.syn = {
		request = globals.request,
		protect_gui = function() end,
		unprotect_gui = function() end,
		crypt = nil,
		secure_call = function(fn: any)
			local target = Spy.unwrap(fn)
			if type(target) == "function" then
				return target()
			end
			return nil
		end,
	}

	globals.setclipboard = function(value: any)
		local text = tostring(Spy.unwrap(value) or "")
		trace:push("call", "setclipboard(...)", nest, { clipboard = text, bytes = #text })
	end
	globals.toclipboard = globals.setclipboard

	local newcWrapped = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }

	local builtinsSnapshot = setmetatable({}, { __mode = "k" }) :: { [any]: boolean }

	local hookRegistry: { [any]: { original: any, replacement: any } } = {}

	local hookInterceptors: { [any]: any } = setmetatable({}, { __mode = "k" })

	local targetHooks: { [any]: { original: any, replacement: any } } = setmetatable({}, { __mode = "k" })

	globals.hookfunction = function(target: any, replacement: any): any
		trace:push("call", "hookfunction(...)", nest, { hook = true })
		if type(target) ~= "function" then return target end
		if type(replacement) ~= "function" then return target end

		targetHooks[target] = { original = target, replacement = replacement }
		hookRegistry[target] = { original = target, replacement = replacement }

		local wrapper = function(...: any): ...any
			return replacement(...)
		end
		hookInterceptors[target] = wrapper

		local function tryReplace(table: any)
			if type(table) ~= "table" then return false end
			for k, v in pairs(table) do
				if v == target then
					rawset(table, k, wrapper)
					return true
				end

				if type(v) == "table" and k ~= "debug" then
					for k2, v2 in pairs(v) do
						if v2 == target then
							rawset(v, k2, wrapper)
							return true
						end
					end
				end
			end
			return false
		end

		local searchEnv = hookSearchEnv
		if not tryReplace(searchEnv) then
			for _, lib in ipairs({ searchEnv.string, searchEnv.table, searchEnv.math }) do
				if tryReplace(lib) then break end
			end
		end

		return target
	end
	globals.hookfunc = globals.hookfunction
	globals.replaceclosure = globals.hookfunction
	globals.restorefunction = function(target: any, original: any?): any
		trace:push("call", "restorefunction(...)", nest, { hook = true })

		local entry = targetHooks[target]
		if entry then
			local interceptor = hookInterceptors[target]
			if interceptor then
				local function tryRestore(table: any)
					if type(table) ~= "table" then return false end
					for k, v in pairs(table) do
						if v == interceptor then
							rawset(table, k, entry.original)
							return true
						end
						if type(v) == "table" and k ~= "debug" then
							for k2, v2 in pairs(v) do
								if v2 == interceptor then
									rawset(v, k2, entry.original)
									return true
								end
							end
						end
					end
					return false
				end
				tryRestore(hookSearchEnv)
				for _, lib in ipairs({ hookSearchEnv.string, hookSearchEnv.table, hookSearchEnv.math }) do
					if tryRestore(lib) then break end
				end
			end
			hookInterceptors[target] = nil
			hookRegistry[target] = nil
			targetHooks[target] = nil
		end
		return target
	end

	local metamethodHooks: { [any]: { [string]: any } } = setmetatable({}, { __mode = "k" })
	globals.hookmetamethod = function(target: any, method: any, hook: any): any
		trace:push("call", "hookmetamethod(...)", nest, { hook = true })
		local methodName = tostring(Spy.unwrap(method) or method)

		if type(target) ~= "table" then return function(...) return ... end end

		if not metamethodHooks[target] then
			metamethodHooks[target] = {}

			local existingMt = getmetatable(target)
			local existingIndex = existingMt and existingMt.__index
			local savedFields: { [any]: any } = {}
			if methodName == "__index" then
				for k, v in pairs(target) do
					savedFields[k] = v
					rawset(target, k, nil)
				end
			end
			local hookActive = false
			local okSet, _ = pcall(setmetatable, target, {
				__index = function(t, k)

					if not hookActive then
						local hooks = metamethodHooks[t]
						if hooks and hooks["__index"] then
							hookActive = true
							local ok, result = pcall(hooks["__index"], t, k)
							hookActive = false
							if ok and result ~= nil then return result end
						end
					end

					if savedFields[k] ~= nil then
						return savedFields[k]
					end

					if existingIndex then
						if type(existingIndex) == "function" then
							return existingIndex(t, k)
						elseif type(existingIndex) == "table" then
							return existingIndex[k]
						end
					end
					return rawget(t, k)
				end,
			})

			if not okSet and methodName == "__index" then

				for k, v in pairs(savedFields) do
					rawset(target, k, v)
				end
			end
		end

		local originalMethod = existingMt and existingMt[methodName]
		metamethodHooks[target][methodName] = hook
		return originalMethod or hook
	end

	local rawMtDecoys: { [any]: any } = setmetatable({}, { __mode = "k" })
	globals.getrawmetatable = function(target: any): any
		if Spy.is(target) then
			local decoy = rawMtDecoys[target]
			if not decoy then
				decoy = {
					__index = function() end,
					__newindex = function() end,
					__namecall = function() end,
					__metatable = "The metatable is locked",
				}
				rawMtDecoys[target] = decoy
			end
			return decoy
		end
		local mt = getmetatable(target)
		if type(mt) == "table" then
			return mt
		end
		return {}
	end
	globals.setrawmetatable = function(target: any, mt: any?): any
		if mt ~= nil then
			setmetatable(target, mt)
		end
		return target
	end
	globals.setreadonly = function() end
	globals.isreadonly = function(): boolean
		return false
	end
	globals.make_writeable = function() end
	globals.make_readonly = function() end

	globals.checkcaller = function(): boolean
		return true
	end
	globals.newcclosure = function(fn: any): any
		if type(fn) ~= "function" then return fn end
		local wrapped = function(...)
			return fn(...)
		end
		newcWrapped[wrapped] = true
		return wrapped
	end
	globals.clonefunction = function(fn: any): any
		if type(fn) ~= "function" then return fn end
		local copy = function(...)
			return fn(...)
		end
		return copy
	end
	globals.getnamecallmethod = function(): string
		return ""
	end
	globals.setnamecallmethod = function() end
	local function collectEnvTree(): { any }
		local out: { any } = {}
		if game == nil then
			return out
		end
		local seen: { [any]: boolean } = {}
		local stack: { any } = { game }
		while #stack > 0 do
			local node = table.remove(stack)
			if node ~= nil and not seen[node] then
				seen[node] = true
				out[#out + 1] = node
				local deeper = parentChildren[node]
				if type(deeper) == "table" then
					for i = #deeper, 1, -1 do
						local child = deeper[i]
						if child ~= nil then
							stack[#stack + 1] = child
						end
					end
				end
			end
		end
		return out
	end

	local ENV_SCRIPT_CLASSES: { [string]: boolean } = {
		Script = true, LocalScript = true, ModuleScript = true,
	}

	local function envInstanceClassOf(node: any): string?
		local ok, descriptor = pcall(Symbol.get, node)
		if ok and type(descriptor) == "table" and type(descriptor.detail) == "table" then
			local className = descriptor.detail.className
			if type(className) == "string" then
				return className
			end
		end
		return nil
	end

	local function collectEnvScripts(moduleOnly: boolean): { any }
		local out: { any } = {}
		for node in pairs(parentChildren) do
			if node ~= nil and node ~= game then
				local className = envInstanceClassOf(node)
				if className == "ModuleScript" or (not moduleOnly and ENV_SCRIPT_CLASSES[className]) then
					out[#out + 1] = node
				end
			end
		end
		local function renderOrder(node: any): number
			local ok, id = pcall(Spy.renderIdOf, node)
			if ok and type(id) == "number" then
				return id
			end
			return 0
		end
		table.sort(out, function(a: any, b: any): boolean
			return renderOrder(a) < renderOrder(b)
		end)
		return out
	end

	local function collectEnvNil(): { any }
		local out: { any } = {}
		local seen: { [any]: boolean } = {}
		for node in pairs(parentChildren) do
			if node ~= nil and node ~= game and not seen[node] then
				seen[node] = true
				if parentOf[node] == nil then
					out[#out + 1] = node
				end
			end
		end
		return out
	end
	globals.getgc = function(includeTables: any?): { any }
		return collectEnvTree()
	end
	globals.getreg = function(): { any }
		return {}
	end
	globals.getinstances = function(): { any }
		return collectEnvTree()
	end
	globals.getnilinstances = function(): { any }
		return collectEnvNil()
	end
	globals.getscripts = function(): { any }
		return collectEnvScripts(false)
	end
	globals.getloadedmodules = function(): { any }
		return collectEnvScripts(true)
	end

	globals.getconnections = function(): { any }
		return {
			{
				Enabled = true,
				Connected = true,
				LuaConnection = true,
				ForeignState = false,
				Disable = function() end,
				Enable = function() end,
				Disconnect = function() end,
				Deactivate = function() end,
				Fire = function(...)
					return ...
				end,
			},
		}
	end
	globals.fireclickdetector = function() end
	globals.fireproximityprompt = function() end
	globals.firetouchinterest = function() end
	globals.firesignal = function() end
	globals.decompile = function(): string
		return "-- decompilation unavailable"
	end
	globals.getcallingscript = function(): any
		return nil
	end
	globals.readclipboard = function(): string
		return ""
	end
	globals.getcustomasset = function(url: any): string
		local target = tostring(Spy.unwrap(url) or "")
		trace:push("call", string.format("getcustomasset(%s)", Serializer.stringLiteral(target)), nest, {
			url = target,
		})
		return "rbxasset://glassluau/" .. tostring(#target)
	end
	globals.getasset = globals.getcustomasset
	globals.gethiddenproperty = function(_instance: any, property: any): any
		trace:push("call", "gethiddenproperty(" .. Spy.pathOf(_instance) .. ", " .. Serializer.value(property, { pretty = false }) .. ")", nest)
		return nil
	end
	globals.sethiddenproperty = function() end
	globals.getfpscap = function(): number
		return 60
	end
	globals.setfpscap = function() end
	globals.isnetworkowner = function(): boolean
		return true
	end
	globals.cloneref = function(instance: any): any
		return instance
	end
	globals.compareinstances = function(a: any, b: any): boolean
		return rawequal(Spy.unwrap(a), Spy.unwrap(b))
	end
	globals.getscriptbytecode = function(_script: any): string
		return string.rep("\0", 64)
	end
	globals.getscriptclosure = function(_script: any): any
		trace:push("call", "getscriptclosure(" .. Spy.pathOf(_script) .. ")", nest)
		return function() end
	end
	globals.getscripthash = function(_script: any): string
		trace:push("call", "getscripthash(" .. Spy.pathOf(_script) .. ")", nest)
		return string.rep("0", 64)
	end
	globals.getscriptfromthread = function(): any
		return nil
	end
	globals.getsenv = function(): any
		return {}
	end
	globals.getmenv = globals.getsenv
	globals.getthreadidentity = function(): number
		return 7
	end
	globals.setthreadidentity = function() end
	globals.getidentity = globals.getthreadidentity
	globals.setidentity = globals.setthreadidentity
	globals.queue_on_teleport = function() end
	globals.queueonteleport = globals.queue_on_teleport
	globals.messagebox = function(): number
		return 0
	end

	globals.gethui = function(): any
		return getService("CoreGui")
	end

	if config.gethuiMode == "function" then

		local callSpy2 = Spy.internalOf(globals.gethui)
		local fnState = {
			config = callSpy2 and callSpy2.config or nil,
			path = "gethui",
		}
		local originalFn = globals.gethui
		local wrapped = function(...: any): any
			return originalFn(...)
		end
		Symbol.tag(wrapped, { kind = "closure", expression = "gethui()", detail = { aliasOf = "gethui" } })
		globals.gethui = wrapped
	else
		local coreGui = getService("CoreGui")
		local callSpy = Spy.internalOf(globals.gethui)
		local originalCall = globals.gethui
		local dual = setmetatable({}, {
			__call = function(_self, ...: any): any
				return originalCall(...)
			end,
			__index = function(_self, key: any): any
				return coreGui[key]
			end,
			__newindex = function(_self, key: any, value: any)
				coreGui[key] = value
			end,
			__iter = function()
				return function()
					return nil
				end
			end,
		})
		Symbol.tag(dual, {
			kind = "closure",
			expression = "gethui",
			typeName = "function",
			detail = { dualNature = true, callable = true, aliasOf = "gethui" },
		})
		globals.gethui = dual
	end

	do
		local probeTargets = {
			"pcall", "ipairs", "getfenv", "setfenv", "error", "assert",
			"select", "tonumber", "tostring", "type", "next", "unpack",
		}
		for _, name in ipairs(probeTargets) do
		local fn = globals[name]
		if type(fn) == "function" then
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
		end
	end
	globals.__wrapFunc = function(f: any): any
		if type(f) ~= "function" then return f end

		local safeNil: any
		safeNil = setmetatable({}, {
			__call = function(): any return nil end,
			__index = function(): any return safeNil end,
			__iter = function(): any
				return function(): any return nil end
			end,
		})
		local t: any = {}
		setmetatable(t :: any, {
			__call = function(_: any, ...: any): any
				return (f :: any)(...)
			end,
			__index = function(_: any, k: any): any

				if type(k) == "string" then
					return safeNil
				end
				return nil
			end,
		})			Symbol.tag(t, { kind = "closure", typeName = "function", expression = "wrapped", detail = { original = f } })
		return t
	end
	globals.firescriptsignal = function() end
	globals.checkclosure = function(fn: any): boolean
		return globals.isexecutorclosure(fn)
	end
	globals.getcallbackvalue = function(): any
		return nil
	end
	globals.getpropertyvalue = function(instance: any, property: any): any
		local ok, value = pcall(function()
			return instance[property]
		end)
		if ok then
			return value
		end
		return nil
	end
	globals.getproperties = function(): { any }
		return {}
	end
	globals.setscriptable = function(): boolean

		return false
	end
	globals.isrbxactive = function(): boolean
		return globals.iswindowactive()
	end
	globals.isgameactive = globals.isrbxactive

	globals.cache = {
		invalidate = function() end,
		replace = function() end,
		iscached = function(): boolean
			return true
		end,
	}

	globals.getexecutorname = globals.identifyexecutor
	globals.is_syn_closure = function(_fn: any): boolean
		return false
	end
	globals.isexecutorclosure = globals.is_syn_closure
	globals.iswindowactive = function(): boolean
		return true
	end
	globals.getwindowsize = function(): (number, number)
		return 1920, 1080
	end
	globals.setclipboard = function() end
	globals.getclipboard = function(): string
		return ""
	end
	globals.setfflag = function() end
	globals.getfflag = function(): string
		return ""
	end
	globals.gethiddenprop = globals.gethiddenproperty
	globals.sethiddenprop = globals.sethiddenproperty
	globals.saveinstance = function() end
	globals.getobjects = function(_asset: any): { any }
		return {}
	end
	globals.getcustomasset = globals.getcustomasset
	globals.rconsoleprint = globals.rconsoleprint or function() end
	globals.rconsolecreate = globals.rconsolecreate or function() end
	globals.rconsoletitle = globals.rconsoletitle or function() end
	globals.rconsoleclear = globals.rconsoleclear or function() end
	globals.rconsoleclose = globals.rconsoleclose or function() end
	globals.rconsoleinput = globals.rconsoleinput or function() return "" end
	globals.rconsolewarn = globals.rconsolewarn or function() end
	globals.rconsoleerr = globals.rconsoleerr or function() end
	globals.secure_call = function(fn: any, ...: any): any
		return fn(...)
	end
	globals.safe_call = globals.secure_call
	globals.setsimulationradius = function() end
	globals.getsimulationradius = function(): number
		return 0
	end

	local function consoleOut(channel: string)
		return function(...)
			if options.checkBudget and options.checkBudget() then
				error("sandbox budget exceeded")
			end
			local count = select("#", ...)
			local text = ""
			if count > 0 then
				local parts = table.create(count)
				for i = 1, count do
					parts[i] = tostring(Spy.unwrap(select(i, ...)) or "")
				end
				text = table.concat(parts, "\t")
			end
			trace:push("output", text, nest, {
				channel = channel,
				args = if #text > 0 then { { text = text, isString = true } } else nil,
			})
		end
	end
	globals.rconsoleprint = consoleOut("rconsoleprint")
	globals.rconsoleinfo = consoleOut("rconsoleinfo")
	globals.rconsolewarn = consoleOut("rconsolewarn")
	globals.rconsoleerr = consoleOut("rconsoleerr")
	globals.rconsolename = function() end
	globals.rconsoleclear = function() end
	globals.rconsolecreate = function() end
	globals.rconsoledestroy = function() end
	globals.mouse1click = function() end
	globals.mouse1press = function() end
	globals.mouse1release = function() end
	globals.mouse2click = function() end
	globals.mousemoveabs = function() end
	globals.mousemoverel = function() end
	globals.keypress = function() end
	globals.keyrelease = function() end

	local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local function base64encode(input: string): string
		return (
			string.gsub(input .. string.rep("\0", (3 - #input % 3) % 3), "...", function(triplet)
				local a, b, c = string.byte(triplet, 1, 3)
				local n = a * 65536 + b * 256 + c
				local chunk = ""
				for shift = 18, 0, -6 do
					local index = bit32.band(bit32.rshift(n, shift), 63) + 1
					chunk ..= string.sub(BASE64, index, index)
				end
				return chunk
			end):sub(1, math.ceil(#input / 3) * 4 - (3 - #input % 3) % 3) .. string.rep("=", (3 - #input % 3) % 3)
		)
	end
	local function base64decode(input: string): string
		local cleaned = string.gsub(input, "[^" .. BASE64 .. "=]", "")
		cleaned = string.gsub(cleaned, "=", "")
		local out = {}
		local bits, count = 0, 0
		for i = 1, #cleaned do
			local index = string.find(BASE64, string.sub(cleaned, i, i), 1, true)
			if index then
				bits = bit32.bor(bit32.lshift(bits, 6), index - 1)
				count += 6
				if count >= 8 then
					count -= 8
					out[#out + 1] = string.char(bit32.band(bit32.rshift(bits, count), 255))
				end
			end
		end
		return table.concat(out)
	end

	globals.crypt = {
		base64encode = function(text: any): string
			return base64encode(tostring(Spy.unwrap(text) or ""))
		end,
		base64decode = function(text: any): string
			return base64decode(tostring(Spy.unwrap(text) or ""))
		end,
		encrypt = function(text: any): string
			return tostring(Spy.unwrap(text) or "")
		end,
		decrypt = function(text: any): string
			return tostring(Spy.unwrap(text) or "")
		end,
		hash = function(text: any): string
			return string.rep("0", 64)
		end,
		random = function(length: any): string
			return string.rep("\0", tonumber(Spy.unwrap(length)) or 16)
		end,
		generatebytes = function(size: any): string
			local n = tonumber(Spy.unwrap(size)) or 16
			return base64encode(string.rep("\0", math.max(0, math.floor(n))))
		end,
		generatekey = function(): string

			return base64encode(string.rep("\0", 32))
		end,
	}
	globals.crypt.base64 = {
		encode = globals.crypt.base64encode,
		decode = globals.crypt.base64decode,
	}
	globals.base64encode = globals.crypt.base64encode
	globals.base64decode = globals.crypt.base64decode
	globals.base64_encode = globals.crypt.base64encode
	globals.base64_decode = globals.crypt.base64decode

	globals.lz4compress = function(text: any): string
		return tostring(Spy.unwrap(text) or "")
	end
	globals.lz4decompress = function(text: any): string
		return tostring(Spy.unwrap(text) or "")
	end

	local luneDebugInfo = debug.info
	local luneTraceback = debug.traceback

	local function isHostFrame(source: any): boolean
		return not (type(source) == "string" and string.sub(source, 1, 7) == "[string")
	end

	local function guestFrameLevel(level: number): number
		local raw = 1
		local seen = 0
		while raw < 200 do
			local source = luneDebugInfo(raw, "s")
			if source == nil then
				break
			end
			if not isHostFrame(source) then
				seen += 1
				if seen >= level then

					return math.max(1, raw - 1)
				end
			end
			raw += 1
		end
		return 1
	end

	globals.debug = {
		traceback = function(msg: any?, level: any?): string
			local startLevel = 1
			if type(level) == "number" and level > 0 then
				startLevel = level
			end
			local start = guestFrameLevel(startLevel)
			local okTrace, text = pcall(luneTraceback, msg, start)
			if not okTrace or type(text) ~= "string" then
				local m = (msg ~= nil) and tostring(msg) or ""
				return m .. "\nstack traceback:"
			end

			local kept: { string } = {}
			local isFirst = true
			for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
				if isFirst then
					kept[#kept + 1] = line
					isFirst = false
				else
					local src = string.match(line, "^(.-):%d+")
					if src == nil or not isHostFrame(src) then
						kept[#kept + 1] = line
					end
				end
			end
			return table.concat(kept, "\n")
		end,

		hookCallback = nil :: ((string, number) -> ())?,
		gethook = function() return nil end,
		sethook = function(fn: any?, _mask: any?, count: any?)
			if type(fn) ~= "function" then
				globals.debug.hookCallback = nil
				return nil
			end
			globals.debug.hookCallback = fn
			local n = (type(count) == "number" and count >= 2) and count or 2
			for _ = 1, n do
				pcall(fn, "line", 1)
			end
			return nil
		end,
		getinfo = function(func: any?, what: string?): any

			local info: { [string]: any } = {
				source = "@Script",
				short_src = "Script",
				currentline = -1,
				what = "C",
				name = nil,
				numparams = 0,
				is_vararg = -1,
				func = func or function() end,
			}
			if func ~= nil and type(func) == "function" then
				info.func = func

				local okA, numParams, isVarArg = pcall(luneDebugInfo, func, "a")
				if okA then
					info.numparams = numParams or 0
					info.is_vararg = isVarArg and 1 or 0
				end

				local okS, source = pcall(luneDebugInfo, func, "s")
				local isC = false
				if okS and source and source == "[C]" then

					isC = true
				end

				local StdlibMod = globals.string and globals.string.byte and Stdlib
				if StdlibMod and StdlibMod.liftedSet then
					isC = isC or StdlibMod.liftedSet[func] == true
				end

				if not isC and okS and source and source ~= "[C]" then

					if string.find(source, "/src/", 1, true)
						or string.find(source, "\\src\\", 1, true) then
						isC = true
					end
				end
				if isC then
					info.what = "C"
				else
					info.what = "Lua"
				end

				if info.what == "C" then
					info.source = "[C]"
					info.short_src = "[C]"
					info.currentline = -1
				end

				local okN, name = pcall(luneDebugInfo, func, "n")
				if okN and name and name ~= "" then
					info.name = name
				end

				if info.what == "Lua" then
					local okL, line = pcall(luneDebugInfo, func, "l")
					if okL and line then
						info.currentline = line
					end
				end
			end
			return info
		end,
		profilebegin = function(name: any) end,
		profileend = function() end,
		setmemorycategory = function() end,
		resetmemorycategory = function() end,
		info = function(target: any, options: string?, ...: any): ...any

			options = options or "sln"

			local original: any = target
			local lookup: any = target
			for _ = 1, 4 do
				local moved = false
				if Spy.is(lookup) then
					local inner = Spy.unwrap(lookup)
					if inner ~= nil and inner ~= lookup then
						lookup = inner
						moved = true
					end
				end
				local descriptor = Symbol.get(lookup)
				local detail = descriptor and descriptor.detail
				if detail ~= nil and type(detail.wrappedFunction) == "function" then
					lookup = detail.wrappedFunction
					moved = true
				end
				if not moved then
					break
				end
			end
			local nameTarget: any = lookup

			local dualAlias: string? = nil
			do
				local FidelityMod = require("./fidelity")
				local descriptor = Symbol.get(target)
				local detail = descriptor and descriptor.detail
				if detail ~= nil and detail.dualNature and type(detail.aliasOf) == "string" then
					dualAlias = detail.aliasOf
				end
				if dualAlias == nil then
					dualAlias = FidelityMod.cname(lookup)
				end
				if dualAlias == nil then
					dualAlias = FidelityMod.cname(target)
				end
			end
			if type(target) == "number" and target < 0 then
				error("invalid argument #1 to 'info' (level must be non-negative)", 2)
			end
			if type(target) ~= "function" and type(target) ~= "number" and dualAlias == nil then

				local okProbe = type(target) == "table"
				if not okProbe then
					error("invalid argument #1 to 'info' (function or level expected)", 2)
				end
			end
			if dualAlias ~= nil then

				local values: { any } = {}
				local opts = tostring(options or "sln")
				for i = 1, #opts do
					local flag = string.sub(opts, i, i)
					if flag == "s" then
						values[#values + 1] = "[C]"
					elseif flag == "l" then
						values[#values + 1] = -1
					elseif flag == "n" then
						values[#values + 1] = dualAlias
					elseif flag == "a" then
						values[#values + 1] = 0
						values[#values + 1] = true
					elseif flag == "f" then
						values[#values + 1] = original
					end
				end
				return table.unpack(values, 1, #values)
			end
			if type(target) == "function" then
				local isEngine = false
				if type(builtinsSnapshot) == "table" and builtinsSnapshot[target] then
					isEngine = true
				end
				local StdlibMod = globals.string and globals.string.byte and Stdlib
				if not isEngine and StdlibMod and StdlibMod.liftedSet and StdlibMod.liftedSet[target] then
					isEngine = true
				end
				if newcWrapped and newcWrapped[target] then
					isEngine = true
				end
				if not isEngine then
					local okSource, source = pcall(luneDebugInfo, target, "s")
					if okSource and type(source) == "string"
						and source ~= "[C]" and source ~= "[string"
						and (string.find(source, "/", 1, true) or string.find(source, "\\", 1, true)
							or source == "stdlib" or source == "roblox" or source == "control"
							or source == "sandbox" or source == "datatypes" or source == "enumitem") then
						isEngine = true
					end
				end
				if isEngine then

					local FidelityMod = require("./fidelity")
					local registered: string? = FidelityMod.cname(target)
					if registered == nil then
						registered = FidelityMod.cname(nameTarget)
					end
					if registered == nil and type(hookSearchEnv) == "table" then

						local function scan(container: any)
							if type(container) ~= "table" then
								return
							end
							for key, value in pairs(container) do
								if value == target and type(key) == "string" then
									registered = key
									return
								end
							end
						end
						scan(hookSearchEnv)
						if registered == nil then
							local mt = getmetatable(hookSearchEnv)
							if type(mt) == "table" then
								scan(rawget(mt, "__index"))
								if registered == nil then
									local proxy = rawget(hookSearchEnv, "_G")
									scan(proxy)
								end
							end
						end
					end
					local values: { any } = {}
					local opts = tostring(options or "sln")
					for i = 1, #opts do
						local flag = string.sub(opts, i, i)
						if flag == "s" then
							values[#values + 1] = "[C]"
						elseif flag == "l" then
							values[#values + 1] = -1
						elseif flag == "n" then
							local name = registered
							if name == nil then
								local okN, luneName = pcall(luneDebugInfo, target, "n")
								if okN and type(luneName) == "string" and luneName ~= "" then
									name = luneName
								end
							end
							values[#values + 1] = name or ""
						elseif flag == "a" then
							values[#values + 1] = 0
							values[#values + 1] = true
						elseif flag == "f" then
							values[#values + 1] = target
						end
					end
					return table.unpack(values, 1, #values)
				end
			end

			local rawTarget: any = if type(target) == "number" then guestFrameLevel(target) else target
			local results = table.pack(luneDebugInfo(rawTarget, options :: any, ...))
			if type(target) == "number" then
				for i = 1, results.n do
					local value = results[i]

					if type(value) == "string" and value ~= "[C]"
						and not string.match(value, '^%[string')
						and (string.find(value, "/", 1, true) or string.find(value, "\\", 1, true)
							or value == "stdlib" or value == "roblox" or value == "control"
							or value == "sandbox" or value == "datatypes" or value == "enumitem"
							or value == "main" or value == "analysis") then
						results[i] = '[string ""]'
					end
				end
			end
			return table.unpack(results, 1, results.n)
		end,
		getconstants = function(func: any?): { any }

			return {}
		end,
		getconstant = function(func: any?, idx: number?): any
			return nil
		end,
		setconstant = function() end,
		getupvalues = function(func: any?): { any }
			return {}
		end,
		getupvalue = function(func: any?, idx: number?): any
			return nil
		end,
		setupvalue = function() end,
		getprotos = function(): { any }
			return {}
		end,
		getproto = function(): any
			return nil
		end,
		getstack = function(): { any }
			return {}
		end,
		setstack = function() end,
		getregistry = function(): { any }
			return {}
		end,
		getmetatable2 = function(obj: any): any
			return getmetatable(obj)
		end,

		dumpheap = function(): { any }
			return {}
		end,
		loadmodule = function(name: any): any
			if type(name) ~= "string" then
				error("invalid argument #1 to 'loadmodule' (string expected)", 2)
			end
			return ""
		end,
		setmetatable = function(obj: any, mt: any): any
			return setmetatable(obj, mt)
		end,
		getmetatable = function(obj: any): any
			return getmetatable(obj)
		end,
		getmemorycategory = function(): string
			return "default"
		end,
		validlevel = 2,
		isvalidlevel = function(level: number?): boolean
			return true
		end,
		dumpcodesize = function(): number
			return 0
		end,
		dumprefs = function(): { any }
			return {}
		end,

		getlocal = function(level: number?, index: number?): (string?, any?)
			if type(level) ~= "number" or type(index) ~= "number" then
				return nil
			end

			local ok, name = pcall(luneDebugInfo, level, "f")
			if ok and name then

				return "local" .. tostring(index), nil
			end
			return nil
		end,
	}

	globals.Drawing = {
		new = function(drawingType: any): any
			local kind = tostring(drawingType or "")
			local props: { [string]: any } = {
				Visible = false,
				ZIndex = 0,
				Transparency = 1,
				Color = globals.Color3.new(1, 1, 1),
				Position = globals.Vector2.new(0, 0),
				Size = globals.Vector2.new(0, 0),
				Thickness = 1,
				Filled = false,
				Text = "",
				Font = 0,
				FontSize = 14,
				TextBounds = globals.Vector2.new(0, 0),
				Center = false,
				Outline = false,
				OutlineColor = globals.Color3.new(0, 0, 0),
				From = globals.Vector2.new(0, 0),
				To = globals.Vector2.new(0, 0),
				Radius = 0,
				NumSides = 0,
				Image = "",
				Remove = function() end,
				Destroy = function() end,
			}
			trace:push("call", "Drawing.new(" .. Serializer.stringLiteral(kind) .. ")", nest)
			return setmetatable(props, {
				__index = function(_t, k: any)
					return props[k]
				end,
				__newindex = function(_t, k: any, v: any)
					props[k] = v
				end,
			})
		end,
		Fonts = { UI = 0, System = 1, Plex = 2, Monospace = 3 },
		newtype = function(kind: any)
			return globals.Drawing.new(kind)
		end,
	}
	globals.WebSocket = {
		connect = function(url: any): any
			local target = tostring(Spy.unwrap(url) or "")

			local normalized = string.gsub(target, "^wss?://", "http://")
			local safe, reason = sft(normalized)
			if not safe then
				trace:push("note", "blocked websocket " .. (reason or "target") .. ": " .. target, nest, { url = target })
				error(string.format("%s - %s", (reason or "blocked target"), JOKE()))
			end
			trace:push("http", target, nest, { method = "WEBSOCKET" })
			return {
				Send = function() end,
				Close = function() end,
				OnMessage = { Connect = function() end },
				OnClose = { Connect = function() end },
			}
		end,
	}

	local Datatypes = require("./datatypes")
	local dtypes = Datatypes.build()
	globals.Vector3 = dtypes.Vector3
	globals.Vector2 = dtypes.Vector2
	globals.Vector2int16 = dtypes.Vector2int16
	globals.Vector3int16 = dtypes.Vector3int16
	globals.UDim = dtypes.UDim
	globals.UDim2 = dtypes.UDim2
	globals.Color3 = dtypes.Color3
	globals.CFrame = dtypes.CFrame
	globals.Region3 = dtypes.Region3
	globals.NumberRange = dtypes.NumberRange
	globals.Rect = dtypes.Rect
	globals.BrickColor = dtypes.BrickColor
	globals.TweenInfo = dtypes.TweenInfo
	globals.Ray = dtypes.Ray
	globals.Faces = dtypes.Faces
	globals.Axes = dtypes.Axes
	globals.ColorSequence = dtypes.ColorSequence
	globals.NumberSequence = dtypes.NumberSequence
	globals.SharedTable = dtypes.SharedTable
	globals.Random = dtypes.Random
	globals.Path2DControlPoint = dtypes.Path2DControlPoint
	globals.UDim2 = dtypes.UDim2
	globals.Font = dtypes.Font
	globals.FontFace = dtypes.Font
	globals.DateTime = dtypes.DateTime
	globals.NumberSequenceKeypoint = dtypes.NumberSequenceKeypoint
	globals.ColorSequenceKeypoint = dtypes.ColorSequenceKeypoint
	globals.PhysicalProperties = dtypes.PhysicalProperties
	globals.Region3int16 = dtypes.Region3int16
	globals.ValueCurveKey = dtypes.ValueCurveKey
	globals.FloatCurveKey = dtypes.FloatCurveKey
	globals.RotationCurveKey = dtypes.RotationCurveKey
	globals.CatalogSearchParams = dtypes.CatalogSearchParams
	globals.PathWaypoint = dtypes.PathWaypoint
	globals.SecurityCapabilities = dtypes.SecurityCapabilities
	globals.RaycastParams = dtypes.RaycastParams
	globals.OverlapParams = dtypes.OverlapParams
	globals.fluxus = {}
	globals.AnnotationRequestType = {
		new = function(...: any): any
			return {}
		end,
	}
	globals.ReflectionService = {
		GetMethodsOfClass = function(...: any): { any } return {} end,
		GetEventsOfClass = function(...: any): { any } return {} end,
		GetClasses = function(...: any): { any } return {} end,
		GetEnums = function(...: any): { any } return {} end,
	}

	globals.getreg = function(): { any }
		return {}
	end

	local function collectEnvTree(): { any }
		local out: { any } = {}
		if game == nil then
			return out
		end
		local seen: { [any]: boolean } = {}
		local stack: { any } = { game }
		while #stack > 0 do
			local node = table.remove(stack)
			if node ~= nil and not seen[node] then
				seen[node] = true
				out[#out + 1] = node
				local deeper = parentChildren[node]
				if type(deeper) == "table" then
					for i = #deeper, 1, -1 do
						local child = deeper[i]
						if child ~= nil then
							stack[#stack + 1] = child
						end
					end
				end
			end
		end
		return out
	end

	local ENV_SCRIPT_CLASSES: { [string]: boolean } = {
		Script = true, LocalScript = true, ModuleScript = true,
	}

	local function envInstanceClassOf(node: any): string?
		local ok, descriptor = pcall(Symbol.get, node)
		if ok and type(descriptor) == "table" and type(descriptor.detail) == "table" then
			local className = descriptor.detail.className
			if type(className) == "string" then
				return className
			end
		end
		return nil
	end

	local function collectEnvScripts(moduleOnly: boolean): { any }
		local out: { any } = {}
		for node in pairs(parentChildren) do
			if node ~= nil and node ~= game then
				local className = envInstanceClassOf(node)
				if className == "ModuleScript" or (not moduleOnly and ENV_SCRIPT_CLASSES[className]) then
					out[#out + 1] = node
				end
			end
		end
		local function renderOrder(node: any): number
			local ok, id = pcall(Spy.renderIdOf, node)
			if ok and type(id) == "number" then
				return id
			end
			return 0
		end
		table.sort(out, function(a: any, b: any): boolean
			return renderOrder(a) < renderOrder(b)
		end)
		return out
	end
	globals.getgc = function(includeTables: any?): { any }
		return collectEnvTree()
	end
	globals.getinstances = function(): { any }
		return collectEnvTree()
	end
	globals.getnilinstances = function(): { any }
		local out: { any } = {}
		local seen: { [any]: boolean } = {}
		for node in pairs(parentChildren) do
			if node ~= nil and node ~= game and not seen[node] then
				seen[node] = true
				if parentOf[node] == nil then
					out[#out + 1] = node
				end
			end
		end
		return out
	end
	globals.getscripts = function(): { any }
		return collectEnvScripts(false)
	end
	globals.getloadedmodules = function(): { any }
		return collectEnvScripts(true)
	end
	globals.getrunningscripts = function(): { any }
		return {}
	end
	globals.getthreadidentity = function(): number
		return 8
	end
	globals.setthreadidentity = function() end
	globals.getidentity = globals.getthreadidentity
	globals.setidentity = globals.setthreadidentity
	globals.getexecutor = function(): string
		return FAKE.executorName
	end
	globals.getexecutorversion = function(): string
		return FAKE.executorVersion
	end
	globals.getexecutorconfig = function(): any
		return { Name = FAKE.executorName, Version = FAKE.executorVersion }
	end
	globals.getexecutorluastring = function(): string
		return "5.1"
	end

	local forcedWritable: { [any]: boolean } = setmetatable({}, { __mode = "k" })
	globals.setreadonly = function(tbl: any, value: any)
		local t = Spy.unwrap(tbl)
		if type(t) ~= "table" then
			return
		end
		if value then
			forcedWritable[t] = nil
			pcall(table.freeze, t)
		else

			forcedWritable[t] = true
		end
	end
	globals.isreadonly = function(tbl: any): boolean
		local t = Spy.unwrap(tbl)
		if type(t) ~= "table" then
			return false
		end
		if forcedWritable[t] then
			return false
		end
		return table.isfrozen(t)
	end
	globals.make_writeable = function() end
	globals.make_readonly = function() end

	local function isEngineCallable(fn: any): boolean
		local descriptor = Symbol.get(fn)
		local detail = descriptor and descriptor.detail
		if detail and detail.dualNature then
			return true
		end
		if Spy.is(fn) then
			local inner = Spy.unwrap(fn)
			if inner ~= nil then
				local innerDescriptor = Symbol.get(inner)
				local innerDetail = innerDescriptor and innerDescriptor.detail
				if innerDetail and innerDetail.dualNature then
					return true
				end
				local FidelityModInner = require("./fidelity")
				if FidelityModInner.isC(inner) then
					return true
				end
			end
			return false
		end
		if type(fn) ~= "function" then
			return false
		end
		if newcWrapped[fn] or builtinsSnapshot[fn] then
			return true
		end
		local StdlibMod = globals.string and globals.string.byte and Stdlib
		if StdlibMod and StdlibMod.liftedSet and StdlibMod.liftedSet[fn] then
			return true
		end
		local ok, source = pcall(debug.info, fn, "s")
		if ok and source == "[C]" then
			return true
		end
		local FidelityMod = require("./fidelity")
		return FidelityMod.isC(fn)
	end

	globals.islclosure = function(fn: any): boolean
		if isEngineCallable(fn) then return false end
		if type(fn) ~= "function" then return false end
		return true
	end
	globals.iscclosure = function(fn: any): boolean
		if isEngineCallable(fn) then return true end
		return false
	end
	globals.isnewclosure = globals.iscclosure

	globals.isexecutorclosure = function(fn: any): boolean
		if type(fn) ~= "function" then return false end

		if newcWrapped[fn] then return true end

		if builtinsSnapshot[fn] then return false end

		local ok, source = pcall(debug.info, fn, "s")
		if ok and source == "[C]" then return false end

		local StdlibMod = globals.string and globals.string.byte and Stdlib
		if StdlibMod and StdlibMod.liftedSet and StdlibMod.liftedSet[fn] then
			return false
		end

		return true
	end
	globals.getnamecallmethod = function(): string
		return ""
	end
	globals.setnamecallmethod = function() end
	globals.checkcaller = function(): boolean
		return true
	end
	globals.iswindowactive = function(): boolean
		return true
	end
	globals.getwindowsize = function(): (number, number)
		return 1920, 1080
	end
	globals.getfpscap = function(): number
		return 60
	end
	globals.setfpscap = function() end
	globals.getsimulationradius = function(): number
		return 1000
	end
	globals.setsimulationradius = function() end
	globals.isnetworkowner = function(): boolean
		return true
	end

	globals.secure_call = function(fn: any, ...: any): any
		return fn(...)
	end
	globals.safe_call = globals.secure_call
	globals.messagebox = function(): number
		return 0
	end
	globals.setclipboard = function(_value: any) end
	globals.getclipboard = function(): string
		return ""
	end
	globals.toclipboard = globals.setclipboard
	globals.readclipboard = function(): string
		return ""
	end
	globals.setfflag = function() end
	globals.getfflag = function(_name: any): string
		return ""
	end
	globals.saveinstance = function() end
	globals.decompile = function(_script: any): string
		return "-- decompilation unavailable"
	end
	globals.getscriptbytecode = function(_script: any): string
		return string.rep("\0", 64)
	end

	globals.getcallingscript = function(): any
		return nil
	end
	globals.getsenv = function(_script: any): any
		return {}
	end
	globals.getmenv = globals.getsenv
	globals.getscriptfromthread = function(): any
		return nil
	end

	globals.getconnections = function(_signal: any): { any }
		return {
			{
				Enabled = true,
				Connected = true,
				LuaConnection = true,
				ForeignState = false,
				Disable = function() end,
				Enable = function() end,
				Disconnect = function() end,
				Deactivate = function() end,
				Fire = function(...)
					return ...
				end,
			},
		}
	end
	globals.fireclickdetector = function() end
	globals.fireproximityprompt = function() end
	globals.firetouchinterest = function() end
	globals.firesignal = function() end
	globals.fireclickdetector = globals.fireclickdetector
	globals.fireproximityprompt = globals.fireproximityprompt
	globals.firetouchinterest = globals.firetouchinterest
	globals.firesignal = globals.firesignal

	globals.mouse1click = function() end
	globals.mouse1press = function() end
	globals.mouse1release = function() end
	globals.mouse2click = function() end
	globals.mouse2press = function() end
	globals.mouse2release = function() end
	globals.mousemoveabs = function() end
	globals.mousemoverel = function() end
	globals.keypress = function() end
	globals.keyrelease = function() end
	globals.iskeydown = function(_key: any): boolean
		return false
	end
	globals.iskeypressed = globals.iskeydown
	globals.ismousedown = function(_button: any): boolean
		return false
	end
	globals.getmouselocation = function(): Vector2
		return globals.Vector2.new(0, 0)
	end
	globals.InputService = globals.UserInputService

	globals.queue_on_teleport = function(_code: any) end
	globals.queueonteleport = globals.queue_on_teleport

	globals.newproxy = function(withMetatable: any?): any

		if withMetatable then
			return newproxy(true)
		end
		return newproxy(false)
	end
	globals.crack_http = function() end

	globals.gethiddenproperty = function(_instance: any, property: any): any
		trace:push("call", "gethiddenproperty(...)", nest)
		return nil
	end
	globals.sethiddenproperty = function() end
	globals.gethiddenprop = globals.gethiddenproperty
	globals.sethiddenprop = globals.sethiddenproperty

	local clonedRefs: { [any]: any } = setmetatable({}, { __mode = "v" })
	globals.cloneref = function(instance: any): any
		local path = Spy.pathOf(instance) or "cloneref(...)"

		local srcInternal = Spy.internalOf(instance)
		local cloneSpy: any
		if srcInternal ~= nil and srcInternal.config ~= nil then
			cloneSpy = Spy.new(
				path .. ":cloneref()",
				srcInternal.config,
				srcInternal.concrete,
				srcInternal.hasConcrete,
				srcInternal.depth
			)
		else
			cloneSpy = Spy.new(path .. ":cloneref()", {
				trace = trace,
				nest = nest,
				maxDepth = config.maxDepth,
				checkBudget = options.checkBudget,
			}, nil, false, 0)
		end
		Symbol.tag(cloneSpy, Symbol.tag(instance) or { kind = "cloneref", expression = path })
		clonedRefs[cloneSpy] = Spy.unwrap(instance) or instance
		return cloneSpy
	end
	globals.compareinstances = function(a: any, b: any): boolean
		local wa = Spy.unwrap(a) or a
		local wb = Spy.unwrap(b) or b

		if rawequal(wa, wb) then return true end

		if clonedRefs[a] or clonedRefs[b] then return false end

		local pathA = Spy.pathOf(a) or ""
		local pathB = Spy.pathOf(b) or ""
		return pathA == pathB and pathA ~= ""
	end

	globals.require = function(target: any): any
		trace:push("call", "require(...)", nest)
		if type(target) == "number" then
			error("Invalid argument #1 to 'require' (ModuleScript expected, got number)", 0)
		end
		return nil
	end

	globals.hash = function(data: any): string?
		if type(data) == "function" then return nil end
		if type(data) == "userdata" then return nil end
		if type(data) == "table" then return nil end
		local str = tostring(data or "")
		local seeds = { 5381, 52711, 37159 }
		local parts: { string } = {}
		for _, seed in ipairs(seeds) do
			local h = seed
			for i = 1, #str do
				h = bit32.band(bit32.lshift(h, 5) + h + string.byte(str, i), 0xFFFFFFFF)
			end
			parts[#parts + 1] = string.format("%08x", h)
		end
		local hex = table.concat(parts)
		while #hex < 96 do
			hex = hex .. string.rep("0", 96 - #hex)
		end
		return string.sub(hex, 1, 96)
	end

	local cloneHashRegistry: { [any]: string } = setmetatable({}, { __mode = "k" })
	globals.getfunctionhash = function(fn: any): string
		local unwrapped = Spy.unwrap(fn)
		if type(unwrapped) ~= "function" then return string.rep("0", 96) end
		if cloneHashRegistry[unwrapped] then
			return cloneHashRegistry[unwrapped]
		end

		local ok, bytecode = pcall(string.dump, unwrapped)
		if ok and type(bytecode) == "string" then
			local h = 5381
			for i = 1, #bytecode do
				h = bit32.band(bit32.lshift(h, 5) + h + string.byte(bytecode, i), 0xFFFFFFFF)
			end

			local result = string.format("%08x", h)
			while #result < 96 do result = result .. string.rep("0", 96 - #result) end
			cloneHashRegistry[unwrapped] = result
			return result
		end

		local h = 0
		local ok2, source = pcall(debug.info, unwrapped, "s")
		local ok3, line = pcall(debug.info, unwrapped, "l")
		local ok4, nup = pcall(debug.info, unwrapped, "u")
		local seed = (ok2 and source or "?") .. ":" .. (ok3 and tostring(line) or "?") .. ":" .. (ok4 and tostring(nup) or "?")
		for i = 1, #seed do
			h = bit32.band(bit32.lshift(h, 5) + h + string.byte(seed, i), 0xFFFFFFFF)
		end
		local result = string.format("%08x", h)
		while #result < 96 do result = result .. string.rep("0", 96 - #result) end
		cloneHashRegistry[unwrapped] = result
		return result
	end

	globals.clonefunction = function(fn: any): any
		if type(fn) ~= "function" then return fn end

		local ok, bytecode = pcall(string.dump, fn)
		local copy
		if ok and type(bytecode) == "string" then
			local loaded = loadstring(bytecode)
			copy = loaded or function(...) return fn(...) end
		else
			copy = function(...)
				return fn(...)
			end
		end
		if newcWrapped[fn] then
			newcWrapped[copy] = true
		end
		return copy
	end

	for _, value in pairs(globals) do
		if type(value) == "function" then
			builtinsSnapshot[value] = true
		end
	end

	globals.__builtinsSnapshot = builtinsSnapshot

	do
		local okP, PropDefaults = pcall(require, "./propdefaults")
		if okP and type(PropDefaults) == "table" and PropDefaults.installResolver ~= nil then
			PropDefaults.installResolver(function(constructor: string, args: { any }): any
				local dt = globals[constructor]
				if type(dt) == "table" and type(dt.new) == "function" then
					return dt.new(unpack(args))
				end
				if constructor == "EnumItem" then
					local category = globals.Enum
					local catTable = category and category[args[1]]
					if catTable ~= nil and args[2] ~= nil then
						return catTable[args[2]]
					end
					error("unknown enum category " .. tostring(args[1]))
				end
				error("no constructor for " .. constructor)
			end)
			local okM, materialized = pcall(function()
				return PropDefaults.materialize()
			end)
			if okM and type(materialized) == "table" then
				materializedDefaults = materialized
			end
		end
	end

	return globals
end

return Roblox
