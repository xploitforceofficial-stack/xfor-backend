local luau = require("@lune/luau")
local LuraphExtract = {}

function LuraphExtract.isLuraphSource(text: string): boolean
	if #text < 500 then return false end

	if text:find("Luraph Obfuscator", 1, true)
		or text:find("Luraph decompression error", 1, true)
		or text:find("does your environment support load/loadstring?", 1, true) then
		return true
	end

	if text:find("Ef=function", 1, true)
		and text:find("while v do if I<=", 1, true) then
		return true
	end

	if text:find("while (%w+) do if (%w+)<=", 1)
		and (
			text:find("buffer.readu8", 1, true)
			or text:find("buffer.readu32", 1, true)
			or text:find("string.byte", 1, true)
			or text:find("string.unpack", 1, true)
		) then
		return true
	end

	if (text:find("while true do if", 1, true) or text:find("repeat if", 1, true))
		and (
			text:find("string.unpack", 1, true)
			or text:find("buffer.readu8", 1, true)
			or text:find("bit32.bxor", 1, true)
		)
		and (
			text:find("return({", 1, true)
			or text:find("return(function", 1, true)
			or text:find("LPH@", 1, true)
			or text:find("setfenv", 1, true)
		) then
		return true
	end

	if text:find("LPH@", 1, true) and text:find("loadstring", 1, true) then
		return true
	end

	return false
end

local OLD_DISPATCH_PATTERN = "while v do if I%<="

local NUM_PATTERNS = {
	{ lhs = "0[xX][%x_]+", rhs = "0[xX][%x_]+" },
	{ lhs = "0[bB][01_]+", rhs = "0[bB][01_]+" },
	{ lhs = "%d[%d_]*", rhs = "%d[%d_]*" },
	{ lhs = "%w+", rhs = "%w+" },
}

function LuraphExtract.patchDispatcher(text: string): string
	local function applyGuards(src: string): string
		local out = src:gsub("while true do", "while true do __LPH_REG_GUARD__();")
		out = out:gsub("(%[%d+%]=)buffer%.", "%1__LPH_BUF__.")
		out = out:gsub("(%[%d+%]=)vector%.", "%1__LPH_VEC__.")
		return out
	end

	local v14 = text:gsub(
		"repeat(%s+)(%w+),(%w+),(%w+),(%w+)=(%w+):(%w+)%((.-)%)",
		"repeat%1%2,%3,%4,%5=%6:%7(%8); __LPH_REG_TRACE__(%4,nil,nil,%2,%3,%5)"
	)
	if v14 ~= text then

		for _, np in ipairs(NUM_PATTERNS) do
			v14 = v14:gsub(
				"while true do if (%w+)==(" .. np.rhs .. ")",
				"while true do __LPH_REG_TRACE__(%1); if %1==%2"
			)
			v14 = v14:gsub(
				"while (%w+) do if (%w+)==(" .. np.rhs .. ")",
				"while %1 do __LPH_REG_TRACE__(%2); if %2==%3"
			)
		end
		return applyGuards(v14)
	end

	local out = text:gsub(
		OLD_DISPATCH_PATTERN,
		"while v do __LPH_REG_TRACE__(I,p,y,L,O,V,f,e); if I<="
	)
	if out ~= text then
		return applyGuards(out)
	end

	for _, np in ipairs(NUM_PATTERNS) do
		out = text:gsub(
			"while (%w+) do if (%w+)<=" .. "(" .. np.lhs .. ")" .. "( then)",
			"while %1 do __LPH_REG_TRACE__(); if %2<=%3%4",
			1
		)
		if out ~= text then
			return applyGuards(out)
		end
	end

	out = text:gsub(
		"while true do if (%w+)<=(%w+)",
		"while true do __LPH_REG_TRACE__(); if %1<=%2",
		1
	)
	if out ~= text then
		return applyGuards(out)
	end

	for _, np in ipairs(NUM_PATTERNS) do
		out = text:gsub(
			"while true do if (%w+)==(" .. np.rhs .. ")",
			"while true do __LPH_REG_TRACE__(%1); if %1==%2",
			1
		)
		if out ~= text then
			return applyGuards(out)
		end
	end

	for _, np in ipairs(NUM_PATTERNS) do
		out = text:gsub(
			"while (%w+) do if (%w+)==(" .. np.rhs .. ")",
			"while %1 do __LPH_REG_TRACE__(%2); if %2==%3",
			1
		)
		if out ~= text then
			return applyGuards(out)
		end
	end

	for _, np in ipairs(NUM_PATTERNS) do
		out = text:gsub(
			"while true do if (%w+)<(" .. np.rhs .. ")",
			"while true do __LPH_REG_TRACE__(); if %1<%2",
			1
		)
		if out ~= text then
			return applyGuards(out)
		end
	end

	for _, np in ipairs(NUM_PATTERNS) do
		out = text:gsub(
			"while true do if (%w+)>(" .. np.rhs .. ")",
			"while true do __LPH_REG_TRACE__(); if %1>%2",
			1
		)
		if out ~= text then
			return applyGuards(out)
		end
	end

	for _, np in ipairs(NUM_PATTERNS) do
		out = text:gsub(
			"repeat if (%w+)([<>]=?)(" .. np.rhs .. ")",
			"repeat __LPH_REG_TRACE__(); if %1%2%3",
			1
		)
		if out ~= text then
			return applyGuards(out)
		end
	end

	local guarded = applyGuards(text)
	if guarded ~= text then
		return guarded
	end
	return text
end

local BYTE_CONCAT_SINGLE = "((%a%a?%[%w[%w_]*%]%s*%.%.%s*%a%a?%[%w[%w_]*%]))"

local BYTE_CONCAT_DEEP = "((%a%a?%[%a%a?%[%w[%w_]*%]%]%s*%.%.%s*%a%a?%[%a%a?%[%w[%w_]*%]%]))"

function LuraphExtract.patchByteConcat(text: string): string

	local out = text:gsub(BYTE_CONCAT_DEEP, "__LPH_STR_TRACE__(%1)")

	out = out:gsub(BYTE_CONCAT_SINGLE, "__LPH_STR_TRACE__(%1)")
	return out
end

local FUNC_PARAMS_PATTERN = "(local function [%a%d_]+%([%a%d_]+,%s?[%a%d_]+).-)"

function LuraphExtract.wrapRegisterParams(text: string): string

	local out = text:gsub(
		"(local function [%a%d_]+%([%a%d_]+,%s?[%a%d_]+)(.-)(local [%a%d_]+,[%a%d_]+,[%a%d_]+,[%a%d_]+.-%]%)?;)(.-[%a%d_]+%s?=%s?%(?function%(%.%.%.)",
		function(pre, middle, params, post)
			local injection = ""
			for var in params:gmatch("[%a%d_]+") do
				var = var:gsub("local ", "")
				if #var == 1 then
					injection = injection .. string.format(
						"local _orig_%s=%s;%s=setmetatable({},{__index=function(_,k)local v=_orig_%s[k] __LPH_REG_READ__(v) return v end});",
						var, var, var, var
					) .. ";"
				end
			end
			return pre .. middle .. params .. injection .. post
		end
	)
	return out
end

function LuraphExtract.extractKTable(source: string): { [string]: string }
	local ktable: { [string]: string } = {}

	for hex, value in source:gmatch('%[0x(%x+)%]%s*=%s*"([^"]*)"') do
		ktable["0x" .. hex] = value
	end

	for escaped in source:gmatch('"([^"\\]*\\x[%da-fA-F]+[^"\\]*)') do
		local decoded = escaped:gsub("\\x(%x%x)", function(h)
			return string.char(tonumber(h, 16) or 0)
		end)
		if #decoded >= 2 then
			ktable[decoded] = decoded
		end
	end

	for idx, value in source:gmatch('%[(%d+)%]%s*=%s*"([^"]*)"') do
		if #value >= 2 then
			ktable["[" .. idx .. "]"] = value
		end
	end

	return ktable
end

function LuraphExtract.findDecodeFunctions(source: string): { { name: string, line: number } }
	local decoders: { { name: string, line: number } } = {}

	local lineNum = 1
	for line in source:gmatch("[^\n]+") do
		local hasXor = line:find("bxor", 1, true) ~= nil
		local hasByte = line:find("string.byte", 1, true) ~= nil
		local hasChar = line:find("string.char", 1, true) ~= nil
		local hasUnpack = line:find("string.unpack", 1, true) ~= nil
		local isFunc = line:find("function", 1, true) ~= nil

		if isFunc and (hasXor or (hasByte and hasChar) or hasUnpack) then
			local name = line:match("function%s+([%a%d_]+)")
				or line:match("([%a%d_]+)%s*=%s*function")
				or "(anonymous)"
			table.insert(decoders, { name = name, line = lineNum })
		end

		lineNum += 1
	end

	return decoders
end

function LuraphExtract.extractEmbeddedChunks(source: string, minLength: number?): { string }
	local minLen = minLength or 400
	local chunks: { string } = {}
	local seen: { [string]: boolean } = {}

	local function consider(s: string)
		if #s < minLen or seen[s] then
			return
		end

		local printable = 0
		local probe = math.min(#s, 256)
		for i = 1, probe do
			local b = string.byte(s, i)
			if (b >= 32 and b <= 126) or b == 9 or b == 10 or b == 13 then
				printable += 1
			end
		end
		if probe > 0 and printable / probe < 0.7 then
			return
		end

		local looksLua = s:find("function", 1, true)
			or s:find("local ", 1, true)
			or s:find("return", 1, true)
			or s:find("while ", 1, true)
			or s:find("LPH", 1, true)
			or s:find("string.", 1, true)
			or s:find("buffer.", 1, true)
		if not looksLua then
			return
		end
		seen[s] = true
		chunks[#chunks + 1] = s
	end

	local level = 0
	while true do
		local open = "[" .. string.rep("=", level) .. "["
		local close = "]" .. string.rep("=", level) .. "]"
		local init = 1
		while true do
			local st = string.find(source, open, init, true)
			if not st then
				break
			end
			local en = string.find(source, close, st + #open, true)
			if not en then
				break
			end
			consider(string.sub(source, st + #open, en - 1))
			init = en + #close
		end
		level += 1
		if level > 8 then
			break
		end
	end

	for str in source:gmatch('"([^"\\]-)"') do
		consider(str)
	end
	for str in source:gmatch("'([^'\\]-)'") do
		consider(str)
	end

	return chunks
end

function LuraphExtract.salvageLoadable(text: string): string?
	if type(text) ~= "string" or #text == 0 then
		return nil
	end
	local okRaw, fnRaw = pcall(luau.load, text, { debugName = "salvage_raw" })
	if okRaw and fnRaw then
		return text
	end

	local needles = {
		"return(function",
		"return({",
		"return function",
		"local function",
		"function(",
		"return;",
		"local ",
	}
	for _, needle in ipairs(needles) do
		local init = 1
		for _ = 1, 8 do
			local at = string.find(text, needle, init, true)
			if not at then
				break
			end
			local cand = string.sub(text, at)
			local ok, fn = pcall(luau.load, cand, { debugName = "salvage" })
			if ok and fn then
				return cand
			end
			init = at + #needle
		end
	end
	return nil
end

return LuraphExtract
