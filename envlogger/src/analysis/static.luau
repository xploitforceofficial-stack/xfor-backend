local Instrument = require("../core/instrument")

local Static = {}

export type Findings = {

	urls: { string },

	webhooks: { string },

	strings: { { text: string, length: number } },

	shells: { string },

	loadstringRefs: number,

	largestString: number,

	stringCount: number,
}

local MAX_TOKENS = 1500000
local MAX_STRINGS = 400
local MAX_STRING_BYTES = 4096
local MAX_URLS = 200

local URL_PATTERN = "https?://[%w%-%._~:/%?#@!%$&%(%)%*%+,;=%%]+"

local function noteUrl(
	urls: { string },
	webhooks: { string },
	seen: { [string]: boolean },
	url: string
)
	local clean = string.match(url, URL_PATTERN)
	if not clean or seen[clean] then
		return
	end
	seen[clean] = true
	if
		string.find(clean, "discord.com/api/webhooks", 1, true)
		or string.find(clean, "discordapp.com/api/webhooks", 1, true)
	then

		if #webhooks < MAX_URLS then
			webhooks[#webhooks + 1] = clean
		end
	elseif #urls < MAX_URLS then
		urls[#urls + 1] = clean
	end
end

local function decodeLiteral(raw: string): string

	if string.sub(raw, 1, 1) == "[" then
		return string.sub(raw, 2, #raw - 1)
	end

	if string.sub(raw, 1, 1) == "`" then
		return string.sub(raw, 2, #raw - 1)
	end

	local quote = string.sub(raw, 1, 1)
	local body = string.sub(raw, 2, #raw - 1)
	local out: { string } = {}
	local i = 1
	local n = #body
	while i <= n do
		local byte = string.byte(body, i)
		if byte ~= 92 then
			out[#out + 1] = string.char(byte)
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
			elseif esc == quote then
				out[#out + 1] = quote
				i += 2
			elseif esc == "x" then
				local hex = string.sub(body, i + 2, i + 3)
				local value = tonumber(hex, 16)
				if value then
					out[#out + 1] = string.char(value)
					i += 4
				else
					out[#out + 1] = "\\x"
					i += 2
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
						out[#out + 1] = "\\u{"
						i += 3
					end
				else
					out[#out + 1] = "\\u"
					i += 2
				end
			elseif esc == "z" then

				i += 2
				while i <= n do
					local c = string.byte(body, i)
					if c == 32 or c == 9 or c == 10 or c == 13 then
						i += 1
					else
						break
					end
				end
			elseif esc >= "0" and esc <= "9" then
				local digits = string.match(string.sub(body, i + 1, i + 3), "^%d%d%d")
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

local function detectShells(tokens: { any }): ({ string }, number)
	local shells: { string } = {}

	local seenShell: { [string]: boolean } = {}
	local function note(shape: string)
		if seenShell[shape] then
			return
		end
		seenShell[shape] = true
		shells[#shells + 1] = shape
	end

	local loadstringRefs = 0

	local first = tokens[1]
	if first and first.raw == "return" then
		local second = tokens[2]
		if second and second.raw == "(" then
			local third = tokens[3]
			if third and third.raw == "{" then
				note("self-invoking table shell (return({...}):f()(...))")
			end
		end
	end

	for i = 1, math.min(#tokens, MAX_TOKENS) do
		local raw = tokens[i].raw
		if raw == "loadstring" or raw == "load" then
			local nextRaw = tokens[i + 1]
			if nextRaw and nextRaw.raw == "(" then
				loadstringRefs += 1
			end
		elseif raw == "HttpGet" or raw == "HttpGetAsync" or raw == "request" or raw == "GetAsync" then
			note("fetches code over HTTP at runtime")
		end
	end

	if loadstringRefs > 0 then

		shells[#shells + 1] = string.format("%d loadstring/load call(s)", loadstringRefs)
	end

	return shells, loadstringRefs
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
		local third = string.sub(encoded, i + 2, i + 2)
		local fourth = string.sub(encoded, i + 3, i + 3)
		local a = B64_VALUE[string.sub(encoded, i, i)]
		local b = B64_VALUE[string.sub(encoded, i + 1, i + 1)]

		local c = if third == "=" then 0 else B64_VALUE[third]
		local d = if fourth == "=" then 0 else B64_VALUE[fourth]
		if a == nil or b == nil or c == nil or d == nil then
			return nil
		end
		local n = a * 262144 + b * 4096 + c * 64 + d
		result[#result + 1] = string.char(n // 65536 % 256)
		if third ~= "=" then
			result[#result + 1] = string.char(n // 256 % 256)
		end
		if fourth ~= "=" then
			result[#result + 1] = string.char(n % 256)
		end
	end
	return table.concat(result)
end

local function decodeHex(encoded: string): string?

	encoded = string.gsub(encoded, "0x", "")
	encoded = string.gsub(encoded, "%s+", "")

	if #encoded == 0 or #encoded % 2 ~= 0 then
		return nil
	end
	if string.match(encoded, "[^0-9a-fA-F]") then
		return nil
	end
	local result: { string } = {}
	for i = 1, #encoded, 2 do
		local byte = tonumber(string.sub(encoded, i, i + 1), 16)
		if not byte then return nil end
		result[#result + 1] = string.char(byte)
	end
	return table.concat(result)
end

local function looksLikeBase64(s: string): boolean
	if #s < 24 then return false end

	if string.match(s, "[^A-Za-z0-9+/=]") then return false end

	local withoutPad = string.gsub(s, "=+$", "")
	if #withoutPad % 4 ~= 0 then return false end

	local charSet: { [string]: boolean } = {}
	for i = 1, math.min(#s, 40) do
		charSet[string.sub(s, i, i)] = true
	end
	local unique = 0
	for _ in pairs(charSet) do unique += 1 end
	return unique >= 8
end

local function looksLikeHexBlob(s: string): boolean
	if #s < 20 then return false end
	if #s % 2 ~= 0 then return false end
	return string.match(s, "^[0-9a-fA-F]+$") ~= nil
end

local function detectEncodedStrings(
	source: string,
	urls: { string },
	webhooks: { string },
	strings: { { text: string, length: number } },
	seenString: { [string]: boolean },
	seenUrl: { [string]: boolean }
): { string }
	local shells: { string } = {}
	local decodedCount = 0

	local sourceLen = #source
	local pos = 1
	while pos <= sourceLen do
		local start = string.find(source, "\\x", pos, true)
		if start == nil then
			break
		end
		local cursor = start
		local hex: { string } = {}
		while true do

			local pair = string.match(source, "^\\x(%x%x)", cursor)
			if pair == nil then
				break
			end
			hex[#hex + 1] = pair
			cursor += 4
		end
		if #hex == 0 then

			pos = start + 2
		else
			pos = cursor

			if #hex >= 8 then
				local decoded = decodeHex(table.concat(hex))
				if decoded and not seenString[decoded] then
					seenString[decoded] = true
					decodedCount += 1
					for url in string.gmatch(decoded, URL_PATTERN) do
						noteUrl(urls, webhooks, seenUrl, url)
					end
				end
			end
		end
	end

	local base64Reported = 0
	for match in string.gmatch(source, "[A-Za-z0-9+/][A-Za-z0-9+/][A-Za-z0-9+/][A-Za-z0-9+=][A-Za-z0-9+=][A-Za-z0-9+=][A-Za-z0-9+=][A-Za-z0-9+=]+") do
		if looksLikeBase64(match) then
			local decoded = decodeBase64(match)
			if decoded and #decoded > 8 and not seenString[decoded] then

				local printable = 0
				local probe = math.min(#decoded, 100)
				for i = 1, probe do
					local b = string.byte(decoded, i)
					if (b >= 32 and b <= 126) or b == 9 or b == 10 then
						printable += 1
					end
				end
				if probe > 0 and printable / probe >= 0.8 then
					seenString[decoded] = true
					decodedCount += 1

					if base64Reported < 5 then
						base64Reported += 1
						shells[#shells + 1] = "base64-encoded payload ("
							.. tostring(#decoded) .. " bytes decoded)"
					end
					for url in string.gmatch(decoded, URL_PATTERN) do
						noteUrl(urls, webhooks, seenUrl, url)
					end
				end
			end
		end
	end

	for match in string.gmatch(source, "[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]+") do
		if looksLikeHexBlob(match) then
			local decoded = decodeHex(match)
			if decoded and #decoded > 8 and not seenString[decoded] then
				local printable = 0
				local probe = math.min(#decoded, 100)
				for i = 1, probe do
					local b = string.byte(decoded, i)
					if (b >= 32 and b <= 126) or b == 9 or b == 10 then
						printable += 1
					end
				end
				if probe > 0 and printable / probe >= 0.8 then
					seenString[decoded] = true
					decodedCount += 1
					for url in string.gmatch(decoded, URL_PATTERN) do
						noteUrl(urls, webhooks, seenUrl, url)
					end
				end
			end
		end
	end

	if decodedCount > 0 then
		shells[#shells + 1] = string.format("%d encoded/encrypted string(s) decoded", decodedCount)
	end

	return shells
end

function Static.analyze(source: string): Findings
	local urls: { string } = {}
	local webhooks: { string } = {}
	local strings: { { text: string, length: number } } = {}
	local largestString = 0
	local stringCount = 0

	local seenUrl: { [string]: boolean } = {}

	for url in string.gmatch(source, URL_PATTERN) do
		noteUrl(urls, webhooks, seenUrl, url)
	end

	local tokens: { any } = {}
	local ok, res = pcall(Instrument.tokenize, source)
	if ok then
		tokens = res
	end

	local seenString: { [string]: boolean } = {}
	if #tokens <= MAX_TOKENS then
		for _, token in ipairs(tokens) do
			if token.kind ~= "str" then
				continue
			end
			local decoded = decodeLiteral(token.raw)
			local length = #decoded
			if length > largestString then
				largestString = length
			end
			for url in string.gmatch(decoded, URL_PATTERN) do
				noteUrl(urls, webhooks, seenUrl, url)
			end
			if length >= 16 and not seenString[decoded] then
				seenString[decoded] = true
				stringCount += 1
				if #strings < MAX_STRINGS then
					strings[#strings + 1] = {
						text = string.sub(decoded, 1, MAX_STRING_BYTES),
						length = length,
					}
				end
			end
		end
	end

	local shells, loadstringRefs = detectShells(tokens)

	local encodedShells = detectEncodedStrings(source, urls, webhooks, strings, seenString, seenUrl)
	for _, shell in ipairs(encodedShells) do
		shells[#shells + 1] = shell
	end

	table.sort(urls)
	table.sort(webhooks)
	table.sort(strings, function(a, b)
		return a.length > b.length
	end)

	return {
		urls = urls,
		webhooks = webhooks,
		strings = strings,
		shells = shells,
		loadstringRefs = loadstringRefs,
		largestString = largestString,
		stringCount = stringCount,
	}
end

return Static
