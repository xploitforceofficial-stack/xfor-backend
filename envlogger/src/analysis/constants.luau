local Instrument = require("../core/instrument")
local Spy = require("../core/spy")

local zlibLib: any = nil
do
	local ok, loaded = pcall(function()
		return require("../../zlib")
	end)
	if ok and type(loaded) == "table" then
		zlibLib = loaded
	end
end

local Constants = {}

local URL_PATTERN = "https?://[%w%-%._~:/%?#@!%$&%(%)%*%+,;=%%]+"

local MAX_CONSTANTS = 6000
local MAX_STRING_BYTES = 8192
local MAX_TOKENS = 1500000

local WEBHOOK_PATTERN = "discord%.com/api/webhooks/%d+/[%w%-_]+"
local ATTACHMENT_PREFIX = "attachment://"

export type Kind = "string" | "number" | "url" | "webhook" | "key" | "hash"

local function classify(value: string): Kind
	if string.find(value, ATTACHMENT_PREFIX, 1, true) then
		return "url"
	end
	if string.find(value, WEBHOOK_PATTERN, 1, false) then
		return "webhook"
	end
	if string.match(value, "^" .. URL_PATTERN .. "$") then
		return "url"
	end

	if #value >= 32 and string.match(value, "^%x+$") then
		return "hash"
	end

	if #value >= 20 and #value <= 256 and string.match(value, "^[A-Za-z0-9%-%_]+$") and string.match(value, "%d") and string.match(value, "%a") then
		return "key"
	end
	return "string"
end

local function printableRatio(value: string): number
	local probe = math.min(#value, 200)
	if probe == 0 then
		return 0
	end
	local printable = 0
	for i = 1, probe do
		local b = string.byte(value, i)
		if (b >= 32 and b <= 126) or b == 9 or b == 10 or b == 13 then
			printable += 1
		end
	end
	return printable / probe
end

local function tryInflate(data: string): string?
	if zlibLib == nil then
		return nil
	end
	if #data < 8 then
		return nil
	end
	local okRaw, raw = pcall(zlibLib.decompressDeflate, data)
	if okRaw and type(raw) == "string" and #raw > 0 then
		return raw
	end
	if string.byte(data, 1) == 0x78 then
		local okZ, z = pcall(zlibLib.decompressZlib, data)
		if okZ and type(z) == "string" and #z > 0 then
			return z
		end
	end
	return nil
end

export type Entry = {
	value: string,
	kind: Kind,
	length: number,
	printable: number,
	sources: { string },
}

local function Registry()
	local seen: { [string]: boolean } = {}
	local list: { Entry } = {}

	local self = {}

	function self.add(value: string, kind: Kind?, source: string): boolean
		if type(value) ~= "string" or #value == 0 then
			return false
		end
		if #value > MAX_STRING_BYTES then
			return false
		end
		if seen[value] then
			return false
		end
		seen[value] = true
		if #list >= MAX_CONSTANTS then
			return false
		end
		list[#list + 1] = {
			value = value,
			kind = kind or classify(value),
			length = #value,
			printable = printableRatio(value),
			sources = { source },
		}
		return true
	end

	function self.has(value: string): boolean
		return seen[value] == true
	end

	function self.dropWhere(predicate: (Entry) -> boolean)
		local kept: { Entry } = {}
		for _, entry in ipairs(list) do
			if not predicate(entry) then
				kept[#kept + 1] = entry
			else
				seen[entry.value] = nil
			end
		end
		list = kept
	end

	function self.count(): number
		return #list
	end

	function self.entries(): { Entry }
		return list
	end

	return self
end

local function decodeLiteral(raw: string): string

	local level = string.match(raw, "^%[(=*)%[")
	if level then
		local opener = "[" .. level .. "["
		local closer = "]" .. level .. "]"
		local body = string.sub(raw, #opener + 1, #raw - #closer)

		if string.sub(body, 1, 1) == "\n" then
			body = string.sub(body, 2)
		elseif string.sub(body, 1, 2) == "\r\n" then
			body = string.sub(body, 3)
		end
		return body
	end

	local quote = string.sub(raw, 1, 1)
	local body = string.sub(raw, 2, #raw - 1)
	local out: { string } = {}
	local i = 1
	local n = #body
	while i <= n do
		local byte = string.byte(body, i)
		if byte ~= 92 then
			out[#out + 1] = string.sub(body, i, i)
			i += 1
		else
			local esc = string.sub(body, i + 1, i + 1)
			if esc == "n" then
				out[#out + 1] = "\n"
				i += 2
			elseif esc == "t" then
				out[#out + 1] = "\t"
				i += 2
			elseif esc == "r" then
				out[#out + 1] = "\r"
				i += 2
			elseif esc == "a" then
				out[#out + 1] = "\a"
				i += 2
			elseif esc == "b" then
				out[#out + 1] = "\b"
				i += 2
			elseif esc == "f" then
				out[#out + 1] = "\f"
				i += 2
			elseif esc == "v" then
				out[#out + 1] = "\v"
				i += 2
			elseif esc == "\\" then
				out[#out + 1] = "\\"
				i += 2
			elseif esc == "'" then
				out[#out + 1] = "'"
				i += 2
			elseif esc == "\"" then
				out[#out + 1] = "\""
				i += 2
			elseif esc == "\n" then
				out[#out + 1] = "\n"
				i += 2
			elseif esc == "x" then
				local hex = string.match(string.sub(body, i + 1), "^%x%x")
				local value = hex and tonumber(hex, 16) or nil
				if value then
					out[#out + 1] = string.char(value)
					i += 2 + #hex
				else
					out[#out + 1] = "\\x"
					i += 2
				end
			elseif esc == "z" then

				i += 1
				while i <= n do
					local c = string.byte(body, i)
					if c == 32 or c == 9 or c == 10 or c == 13 then
						i += 1
					else
						break
					end
				end
			elseif esc == "u" then
				local close = string.find(body, "}", i + 2, true)
				if close then
					local value = tonumber(string.sub(body, i + 3, close - 1), 16)
					if value and value <= 0x10FFFF then
						if value < 0x80 then
							out[#out + 1] = string.char(value)
						elseif value < 0x800 then
							out[#out + 1] = string.char(0xC0 + value // 0x40, 0x80 + value % 0x40)
						elseif value < 0x10000 then
							out[#out + 1] = string.char(
								0xE0 + value // 0x1000,
								0x80 + (value // 0x40) % 0x40,
								0x80 + value % 0x40
							)
						else
							out[#out + 1] = string.char(
								0xF0 + value // 0x40000,
								0x80 + (value // 0x1000) % 0x40,
								0x80 + (value // 0x40) % 0x40,
								0x80 + value % 0x40
							)
						end
						i = close + 1
					else
						out[#out + 1] = "\\u"
						i += 2
					end
				else
					out[#out + 1] = "\\u"
					i += 2
				end
			elseif string.byte(esc) and string.byte(esc) >= 48 and string.byte(esc) <= 57 then

				local digits = string.match(string.sub(body, i + 1, i + 3), "^%d%d?%d?")
				local value = tonumber(digits)
				if value and value <= 255 then
					out[#out + 1] = string.char(value)
					i += 1 + #digits
				else
					out[#out + 1] = esc
					i += 2
				end
			else
				out[#out + 1] = "\\" .. esc
				i += 2
			end
		end
	end
	return table.concat(out)
end

local function passStaticLiterals(source: string, reg, stats)
	local ok, tokens = pcall(Instrument.tokenize, source)
	if not ok or type(tokens) ~= "table" or #tokens > MAX_TOKENS then
		if not ok then
			stats.notes[#stats.notes + 1] = "tokenizer failed on source; literal pass skipped"
		else
			stats.notes[#stats.notes + 1] = "source too large for literal pass"
		end
		return
	end

	local strings = 0
	local numbers = 0
	for _, token in ipairs(tokens) do
		if token.kind == "str" then
			local value = decodeLiteral(token.raw)
			if #value > 0 and reg.add(value, nil, "literal") then
				strings += 1
			end
		elseif token.kind == "num" then
			local n = tonumber(token.raw)
			if n and reg.add(tostring(n), "number", "literal") then
				numbers += 1
			end
		end
	end
	stats.literals = { strings = strings, numbers = numbers }
end

local function tryByteArray(values: { number }): string?
	if #values < 4 or #values > 8192 then
		return nil
	end
	local ratio = 0
	for _, b in ipairs(values) do
		if b ~= math.floor(b) or b < 0 or b > 255 then
			return nil
		end
		if (b >= 32 and b <= 126) or b == 10 or b == 13 or b == 9 then
			ratio += 1
		end
	end
	if ratio / #values < 0.9 then
		return nil
	end
	local out: { string } = {}
	for _, b in ipairs(values) do
		out[#out + 1] = string.char(b)
	end
	return table.concat(out)
end

local function passByteArrays(source: string, reg, stats)
	local recovered = 0
	local byteValues: { [number]: boolean } = {}

	for call in string.gmatch(source, "string%.char%b()") do
		local values: { number } = {}
		for num in string.gmatch(call, "%d+") do
			values[#values + 1] = tonumber(num) :: number
		end
		local decoded = tryByteArray(values)
		if decoded and reg.add(decoded, nil, "string.char") then
			recovered += 1
			for _, b in ipairs(values) do
				byteValues[b] = true
			end
		end
	end

	for table_ in string.gmatch(source, "%{%s*%d+%s*(,[^%{%}]*,[^%{%}]*)%}") do
		local values: { number } = {}
		local ok = pcall(function()
			for num in string.gmatch("{" .. table_ .. "}", "%-?%d+") do
				values[#values + 1] = tonumber(num) :: number
			end
		end)
		if ok then
			local decoded = tryByteArray(values)
			if decoded and reg.add(decoded, nil, "byte-table") then
				recovered += 1
				for _, b in ipairs(values) do
					byteValues[b] = true
				end
			end
		end
	end

	reg.dropWhere(function(entry)
		return entry.kind == "number"
			and entry.length <= 3
			and tonumber(entry.value) ~= nil
			and byteValues[tonumber(entry.value) :: number] == true
	end)

	stats.byteTables = recovered
end

local B64_VALUE: { [string]: number } = {}
do
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for index = 1, #chars do
		B64_VALUE[string.sub(chars, index, index)] = index - 1
	end
end

local function decodeBase64(encoded: string): string?
	encoded = string.gsub(encoded, "%s+", "")
	if #encoded == 0 or #encoded % 4 ~= 0 then
		return nil
	end
	if string.match(encoded, "[^A-Za-z0-9+/=]") then
		return nil
	end
	local result: { string } = {}
	for i = 1, #encoded, 4 do
		local a = B64_VALUE[string.sub(encoded, i, i)]
		local b = B64_VALUE[string.sub(encoded, i + 1, i + 1)]
		local c3 = string.sub(encoded, i + 2, i + 2)
		local d4 = string.sub(encoded, i + 3, i + 3)
		local c = if c3 == "=" then 0 elseif B64_VALUE[c3] then B64_VALUE[c3] else nil
		local d = if d4 == "=" then 0 elseif B64_VALUE[d4] then B64_VALUE[d4] else nil
		if a == nil or b == nil or c == nil or d == nil then
			return nil
		end
		local n = a * 262144 + b * 4096 + c * 64 + d
		result[#result + 1] = string.char(n // 65536 % 256)
		if c3 ~= "=" then
			result[#result + 1] = string.char(n // 256 % 256)
		end
		if d4 ~= "=" then
			result[#result + 1] = string.char(n % 256)
		end
	end
	return table.concat(result)
end

local function decodeHex(encoded: string): string?
	if #encoded == 0 or #encoded % 2 ~= 0 then
		return nil
	end
	local result: { string } = {}
	for i = 1, #encoded, 2 do
		local byte = tonumber(string.sub(encoded, i, i + 1), 16)
		if not byte then
			return nil
		end
		result[#result + 1] = string.char(byte)
	end
	return table.concat(result)
end

local function decodeEscapeRun(text: string): string?

	local function utf8Encode(cp: number): string
		if cp < 0x80 then
			return string.char(cp)
		elseif cp < 0x800 then
			return string.char(192 + math.floor(cp / 64), 128 + (cp % 64))
		elseif cp < 0x10000 then
			return string.char(
				224 + math.floor(cp / 4096),
				128 + math.floor((cp % 4096) / 64),
				128 + (cp % 64)
			)
		else
			return string.char(
				240 + math.floor(cp / 262144),
				128 + math.floor((cp % 262144) / 4096),
				128 + math.floor((cp % 4096) / 64),
				128 + (cp % 64)
			)
		end
	end
	local parts: { string } = {}
	local i = 1
	local n = #text
	while i <= n do
		local c = string.sub(text, i, i)
		if c == "\\" then
			local c2 = string.sub(text, i + 1, i + 1)
			if c2 == "x" then
				local hx = string.match(text, "^\\x(%x%x)", i)
				if hx then
					parts[#parts + 1] = string.char(tonumber(hx, 16) :: number)
					i += 4
					continue
				end
				return nil
			elseif c2 == "u" then
				local hex = string.match(text, "^\\u%x*%{(%x+)%}", i)
				if not hex then
					hex = string.match(text, "^\\u%x*%{(.-)%}", i)
				end
				if hex and #hex > 0 then
					local cp = tonumber(hex, 16)
					if cp then
						parts[#parts + 1] = utf8Encode(cp)
						i = (string.find(text, "}", i, true) or i) + 1
						continue
					end
				end
				return nil
			elseif c2 == "z" then
				i += 2
				while i <= n do
					local b = string.byte(text, i)
					if b == 32 or b == 9 or b == 10 or b == 13 or b == 11 or b == 12 then
						i += 1
					else
						break
					end
				end
				continue
			end
			local dec = string.match(text, "^\\(%d%d%d)", i)
			if dec then
				local v = tonumber(dec)
				if v and v <= 255 then
					parts[#parts + 1] = string.char(v)
					i += 4
					continue
				end
			end
			local simple = string.match(text, "^\\([ntr\\'\"])$", i)
			if simple then
				local map = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ["'"] = "'", ['"'] = '"' }
				parts[#parts + 1] = map[simple] or simple
				i += 2
				continue
			end
			return nil
		else
			parts[#parts + 1] = c
			i += 1
		end
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts)
end

local function looksLikeBase64(s: string): boolean
	if #s < 16 then
		return false
	end
	if string.match(s, "[^A-Za-z0-9+/=]") then
		return false
	end

	if #s % 4 ~= 0 then
		return false
	end
	local charSet: { [string]: boolean } = {}
	for i = 1, math.min(#s, 40) do
		charSet[string.sub(s, i, i)] = true
	end
	local unique = 0
	for _ in pairs(charSet) do
		unique += 1
	end
	return unique >= 8
end

local function passEncoded(source: string, reg, stats, worklist: { string }?)
	local recovered = 0

	local own: { string } = {}
	if worklist == nil then
		worklist = own
		for _, entry in ipairs(reg.entries()) do
			if entry.length >= 12 then
				worklist[#worklist + 1] = entry.value
			end
		end
	end

	local budget = 4000
	local rounds = 0
	while #worklist > 0 and budget > 0 do
		budget -= 1
		local item = table.remove(worklist)
		if rounds < 5000 and #item <= 65536 then
			rounds += 1

			if looksLikeBase64(item) then
				local decoded = decodeBase64(item)
				if decoded and #decoded >= 4 and printableRatio(decoded) >= 0.7 and not reg.has(decoded) then
					if reg.add(decoded, nil, "base64") then
						recovered += 1
						worklist[#worklist + 1] = decoded
					end
				end
			end

			if #item >= 16 and #item % 2 == 0 and string.match(item, "^%x+$") then
				local decoded = decodeHex(item)
				if decoded and #decoded >= 4 and printableRatio(decoded) >= 0.7 and not reg.has(decoded) then
					if reg.add(decoded, nil, "hex") then
						recovered += 1
						worklist[#worklist + 1] = decoded
					end
				end
			end

			if string.find(item, "\\x", 1, true) or string.find(item, "\\1", 1, true) then
				local decoded = decodeEscapeRun(item)
				if decoded and #decoded >= 4 and not reg.has(decoded) then
					if reg.add(decoded, nil, "escapes") then
						recovered += 1
						worklist[#worklist + 1] = decoded
					end
				end
			end

			if #item >= 16 and #item % 2 == 0 and string.match(item, "^%x+$") then
				local bin = decodeHex(item)
				if bin then
					local inflated = tryInflate(bin)
					if inflated and #inflated >= 4 and printableRatio(inflated) >= 0.6 and not reg.has(inflated) then
						if reg.add(inflated, nil, "inflate-hex") then
							recovered += 1
							worklist[#worklist + 1] = inflated
						end
					end
				end
			end

			if looksLikeBase64(item) then
				local bin = decodeBase64(item)
				if bin and #bin >= 8 then
					local inflated = tryInflate(bin)
					if inflated and #inflated >= 4 and printableRatio(inflated) >= 0.6 and not reg.has(inflated) then
						if reg.add(inflated, nil, "inflate-b64") then
							recovered += 1
							worklist[#worklist + 1] = inflated
						end
					end
				end
			end

			for url in string.gmatch(item, URL_PATTERN) do
				reg.add(url, "url", "embedded")
			end
		end
	end

	stats.encoded = recovered
end

local KNOWN_PLAINTEXTS = { "loadstring", "getgenv", "HttpGet", "function", "Instance", "workspace", "return", "string" }

local function xorWith(value: string, key: string): string
	local out: { string } = {}
	local klen = #key
	for i = 1, #value do
		local b = string.byte(value, i)
		local k = string.byte(key, ((i - 1) % klen) + 1)
		out[#out + 1] = string.char(bit32.bxor(b, k))
	end
	return table.concat(out)
end

local function passCompressed(reg, stats)
	if zlibLib == nil then
		return
	end
	local recovered = 0
	local candidates: { string } = {}
	for _, entry in ipairs(reg.entries()) do

		if entry.length >= 24 and entry.printable < 0.75 then
			candidates[#candidates + 1] = entry.value
			if #candidates >= 600 then
				break
			end
		end
	end
	for _, blob in ipairs(candidates) do
		local inflated = tryInflate(blob)
		if inflated and #inflated >= 4 and not reg.has(inflated) then
			if reg.add(inflated, nil, "inflated") then
				recovered += 1
			end
		end
	end
	stats.compressed = recovered
end

local function passXorKeys(source: string, reg, stats)
	local keysFound: { string } = {}

	local candidates: { string } = {}
	for _, entry in ipairs(reg.entries()) do
		local v = entry.value
		if #v >= 1 and #v <= 64 and entry.printable >= 0.9 then
			candidates[#candidates + 1] = v
		end
	end
	if #candidates > 400 then
		stats.xorKeys = { keys = keysFound, tested = 0 }
		return
	end

	local tested = 0
	for _, key in ipairs(candidates) do

		for _, pt in ipairs(KNOWN_PLAINTEXTS) do
			local marker = xorWith(pt, key)
			if #marker >= 4 and string.find(source, marker, 1, true) then
				keysFound[#keysFound + 1] = key
				break
			end
		end
		tested += 1
	end

	local encryptedLike: { string } = {}
	for _, entry in ipairs(reg.entries()) do
		local v = entry.value
		if #v >= 8 and printableRatio(v) < 0.5 then
			encryptedLike[#encryptedLike + 1] = v
			if #encryptedLike >= 50 then
				break
			end
		end
	end
	for _, literal in ipairs(encryptedLike) do
		for keyByte = 1, 255 do
			local decoded = xorWith(string.sub(literal, 1, 64), string.char(keyByte))
			if printableRatio(decoded) >= 0.95 then
				local full = xorWith(literal, string.char(keyByte))
				if not reg.has(full) and reg.add(full, nil, "xor-1byte:" .. tostring(keyByte)) then
					recoveredKeys(keysFound, string.char(keyByte))
				end
				break
			end
		end
	end

	stats.xorKeys = { keys = keysFound, tested = tested }
end

function recoveredKeys(_list, _key)

end

local function passPackedTables(reg, stats)
	local recovered = 0

	for _, entry in ipairs(reg.entries()) do
		local blob = entry.value
		if #blob >= 16 and entry.printable >= 0.5 then
			local i = 1
			local n = #blob
			local run: { string } = {}
			while i <= n do
				local lenByte = string.byte(blob, i)

				if lenByte >= 1 and lenByte <= 40 and i + lenByte <= n then
					local candidate = string.sub(blob, i + 1, i + lenByte)
					if
						string.match(candidate, "^[%w_%.%%:%d%p%s]+$") ~= nil
						and printableRatio(candidate) >= 0.9
					then
						if #candidate >= 2 then
							run[#run + 1] = candidate
						end
						i += lenByte + 1
						continue
					end
				end
				i += 1
			end

			local identifierLike = false
			for _, name in ipairs(run) do
				if string.match(name, "^[%a_][%w_%.]*$") then
					identifierLike = true
					break
				end
			end
			if #run >= 3 and identifierLike then
				for _, name in ipairs(run) do
					if reg.add(name, nil, "packed-table") then
						recovered += 1
					end
				end
			end
		end
	end

	stats.packedTables = recovered
end

	local function passDynamic(result: any, reg, stats)
		local stageSourceSeen: { [string]: boolean } = {}
		local function stageHasRegistered(_reg: any, src: string): boolean
			if stageSourceSeen[src] then
				return true
			end
			stageSourceSeen[src] = true
			return false
		end

	local recovered = 0
	if type(result) ~= "table" then
		return
	end

	local dyn = result.decryptedStrings
	if type(dyn) == "table" then
		for _, value in ipairs(dyn) do
			if type(value) == "string" and reg.add(value, nil, "runtime-decrypted") then
				recovered += 1
			end
		end
	end

	local st = result.stringTable
	if type(st) == "table" then
		for _, value in pairs(st) do
			if type(value) == "string" and reg.add(value, nil, "runtime-stringtable") then
				recovered += 1
			end
		end
	end

	if type(result.stages) == "table" then
		for _, stage in ipairs(result.stages) do
			local src = if type(stage) == "table" then stage.source else nil
			if type(src) == "string" and #src > 0 and not stageHasRegistered(reg, src) then
				stats.stages = (stats.stages or 0) + 1

				passStaticLiterals(src, reg, stats)
				passEncoded(src, reg, stats)
				passByteArrays(src, reg, stats)
			end
		end
	end

	if type(result.outputs) == "table" then
		for _, output in ipairs(result.outputs) do
			local text = if type(output) == "table" then output.text else nil
			if type(text) == "string" and #text >= 4 and reg.add(text, nil, "script-output") then
				recovered += 1
			end
		end
	end

	stats.dynamic = recovered
end

export type Report = {
	constants: { Entry },
	stats: {
		literals: { strings: number, numbers: number }?,
		byteTables: number?,
		encoded: number?,
		dynamic: number?,
		stages: number?,
		xorKeys: { keys: { string }, tested: number }?,
		notes: { string },
	},
	summary: {
		total: number,
		byKind: { [string]: number },
		urls: { string },
		webhooks: { string },
	},
}

function Constants.analyze(source: string, sandboxResult: any?): Report
	local reg = Registry()
	local emptyNotes: { string } = {}
	local stats = { notes = emptyNotes }

	passStaticLiterals(source, reg, stats)
	passByteArrays(source, reg, stats)
	passEncoded(source, reg, stats)
	passCompressed(reg, stats)
	passXorKeys(source, reg, stats)
	passPackedTables(reg, stats)

	if sandboxResult then
		passDynamic(sandboxResult, reg, stats)
	end

	local byKind: { [string]: number } = { string = 0, number = 0, url = 0, webhook = 0, key = 0, hash = 0 }
	local urls: { string } = {}
	local webhooks: { string } = {}
	local entries = reg.entries()
	for _, entry in ipairs(entries) do
		byKind[entry.kind] = (byKind[entry.kind] or 0) + 1
		if entry.kind == "url" and #urls < 100 then
			urls[#urls + 1] = entry.value
		elseif entry.kind == "webhook" and #webhooks < 50 then
			webhooks[#webhooks + 1] = entry.value
		end
	end

	return {
		constants = entries,
		stats = stats,
		summary = {
			total = #entries,
			byKind = byKind,
			urls = urls,
			webhooks = webhooks,
		},
	}
end

local function luaQuote(value: string): string

	if not string.find(value, "\n", 1, true) and not string.find(value, "\r", 1, true) then
		local safe = string.gsub(value, "[\"\\]", "\\%1")
		safe = string.gsub(safe, "%z", "\\0")

		safe = string.gsub(safe, "%c", function(c)
			return string.format("\\%d", string.byte(c))
		end)
		return "\"" .. safe .. "\""
	end

	local level = 0
	while string.find(value, "]" .. string.rep("=", level) .. "]", 1, true) do
		level += 1
	end
	local pad = string.rep("=", level)
	return "[" .. pad .. "[" .. value .. "]" .. pad .. "]"
end

function Constants.render(report: Report): string
	local lines: { string } = {}
	lines[#lines + 1] = "-- fuhed at OmniDBF .gg/odbf"
	lines[#lines + 1] = ""

	local kindRank: { [string]: number } = { webhook = 0, url = 1, key = 2, hash = 3, string = 4, number = 5 }
	local ordered: { Entry } = {}
	for _, entry in ipairs(report.constants) do
		ordered[#ordered + 1] = entry
	end
	table.sort(ordered, function(a, b)
		local ra = kindRank[a.kind] or 6
		local rb = kindRank[b.kind] or 6
		if ra ~= rb then
			return ra < rb
		end
		if a.kind == "number" then

			return (tonumber(a.value) or 0) < (tonumber(b.value) or 0)
		end
		if a.length ~= b.length then
			return a.length > b.length
		end
		return a.value < b.value
	end)

	local RENDER_CAP = 3000
	local renderedCount = math.min(#ordered, RENDER_CAP)
	lines[#lines + 1] = "return {"
	for i = 1, renderedCount do
		local entry = ordered[i]
		if entry.kind == "number" then
			local n = tonumber(entry.value)
			if n and n == n then
				lines[#lines + 1] = "    " .. tostring(n) .. ","
				continue
			end
		end
		lines[#lines + 1] = "    " .. luaQuote(entry.value) .. ","
	end
	lines[#lines + 1] = "}"

	return table.concat(lines, "\n")
end

local _ = Spy

return Constants
