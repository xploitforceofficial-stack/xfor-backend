local Beautifier = {}

export type Options = {

	indent: string?,

	maxInline: number?,

	maxInlineItems: number?,
}

type Token = {
	kind: "kw" | "id" | "num" | "str" | "comment" | "sym",
	raw: string,
}

local KEYWORDS: { [string]: boolean } = {
	["and"] = true, ["break"] = true, ["continue"] = true, ["do"] = true,
	["else"] = true, ["elseif"] = true, ["end"] = true, ["false"] = true,
	["for"] = true, ["function"] = true, ["if"] = true, ["in"] = true,
	["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
	["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
	["until"] = true, ["while"] = true,
}

local SYMBOLS = {
	"...", "<<=", ">>=", "==", "~=", "<=", ">=", "<<", ">>", "..", "::",
	"+=", "-=", "*=", "/=", "//", "%=", "^=", "??", "->", "=>",
	"(", ")", "[", "]", "{", "}", ";", ",", ":", ".", "=", "+", "-",
	"*", "/", "%", "^", "#", "<", ">", "~", "&", "|", "?", "!", "@",
}

local function isIdentStart(byte: number): boolean
	return (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) or byte == 95
end

local function isIdentChar(byte: number): boolean
	return isIdentStart(byte) or (byte >= 48 and byte <= 57)
end

local function isDigit(byte: number): boolean
	return byte >= 48 and byte <= 57
end

local function isWhitespaceByte(byte: number): boolean
	return byte == 32 or byte == 9 or byte == 10 or byte == 13 or byte == 11 or byte == 12
end
local function readLongBracket(source: string, i: number): (string?, number?)
	local equals = 0
	local cursor = i + 1
	while string.sub(source, cursor, cursor) == "=" do
		equals += 1
		cursor += 1
	end
	if string.sub(source, cursor, cursor) ~= "[" then
		return nil
	end
	local closer = "]" .. string.rep("=", equals) .. "]"
	local closeAt = string.find(source, closer, cursor + 1, true)
	if not closeAt then
		return string.sub(source, i), #source + 1
	end
	return string.sub(source, i, closeAt + #closer - 1), closeAt + #closer
end

local function tokenize(source: string): { Token }
	local tokens: { Token } = {}

	local pendingNl = 0
	local n = #source
	local i = 1

	while i <= n do
		local byte = string.byte(source, i)

		if isWhitespaceByte(byte) then
			local nl = 0
			while i <= n and isWhitespaceByte(string.byte(source, i) or 0) do
				if string.byte(source, i) == 10 then
					nl += 1
				end
				i += 1
			end

			if i <= n then
				pendingNl = nl
			end

		elseif byte == 45 and string.sub(source, i + 1, i + 1) == "-" then
			if string.sub(source, i + 2, i + 2) == "[" then

				local raw, nextAt = readLongBracket(source, i + 2)
				if raw then
					tokens[#tokens + 1] = { kind = "comment", raw = "--" .. raw, nl = pendingNl }
					pendingNl = 0
					i = nextAt
				else
					tokens[#tokens + 1] = { kind = "comment", raw = string.sub(source, i), nl = pendingNl }
					break
				end
			else

				local endAt = string.find(source, "\n", i, true) or (n + 1)
				tokens[#tokens + 1] = {
					kind = "comment",
					raw = string.sub(source, i, endAt - 1) .. (if endAt <= n then "\n" else ""),
					nl = pendingNl,
				}
				pendingNl = 0
				i = endAt
			end

		elseif byte == 34 or byte == 39 then
			local quote = string.char(byte)
			local cursor = i + 1
			while cursor <= n do
				local c = string.sub(source, cursor, cursor)
				if c == "\\" then
					cursor += 2
				elseif c == quote then
					break
				else
					cursor += 1
				end
			end
			tokens[#tokens + 1] = {
				kind = "str",
				raw = string.sub(source, i, math.min(cursor, n)),
				nl = pendingNl,
			}
			pendingNl = 0
			i = math.min(cursor, n) + 1

		elseif byte == 91 then
			local raw, nextAt = readLongBracket(source, i)
			if raw then
				tokens[#tokens + 1] = { kind = "str", raw = raw, nl = pendingNl }
				pendingNl = 0
				i = nextAt
			else
				tokens[#tokens + 1] = { kind = "sym", raw = "[", nl = pendingNl }
				pendingNl = 0
				i += 1
			end

		elseif byte == 96 then
			local cursor = i + 1
			local braces = 0
			while cursor <= n do
				local c = string.sub(source, cursor, cursor)
				if c == "\\" then
					cursor += 2
				elseif c == "{" then
					braces += 1
					cursor += 1
				elseif c == "}" and braces > 0 then
					braces -= 1
					cursor += 1
				elseif c == "`" and braces == 0 then
					break
				else
					cursor += 1
				end
			end
			tokens[#tokens + 1] = {
				kind = "str",
				raw = string.sub(source, i, math.min(cursor, n)),
				nl = pendingNl,
			}
			pendingNl = 0
			i = math.min(cursor, n) + 1

		elseif isDigit(byte) or (byte == 46 and isDigit(string.byte(source, i + 1) or 0)) then
			local cursor = i
			if string.sub(source, i, i + 1) == "0x" or string.sub(source, i, i + 1) == "0X" then
				cursor += 2
				while string.match(string.sub(source, cursor, cursor), "[%x]") do
					cursor += 1
				end
			elseif string.sub(source, i, i + 1) == "0b" or string.sub(source, i, i + 1) == "0B" then
				cursor += 2
				while string.sub(source, cursor, cursor) == "0" or string.sub(source, cursor, cursor) == "1" do
					cursor += 1
				end
			else
				while isDigit(string.byte(source, cursor) or 0) do
					cursor += 1
				end
				if string.sub(source, cursor, cursor) == "." then
					cursor += 1
					while isDigit(string.byte(source, cursor) or 0) do
						cursor += 1
					end
				end
				local exponent = string.sub(source, cursor, cursor)
				if exponent == "e" or exponent == "E" then
					local after = cursor + 1
					local sign = string.sub(source, after, after)
					if sign == "+" or sign == "-" then
						after += 1
					end
					if isDigit(string.byte(source, after) or 0) then
						cursor = after
						while isDigit(string.byte(source, cursor) or 0) do
							cursor += 1
						end
					end
				end
			end
			tokens[#tokens + 1] = { kind = "num", raw = string.sub(source, i, cursor - 1), nl = pendingNl }
			pendingNl = 0
			i = cursor

		elseif isIdentStart(byte) then
			local cursor = i + 1
			while isIdentChar(string.byte(source, cursor) or 0) do
				cursor += 1
			end
			local raw = string.sub(source, i, cursor - 1)
			tokens[#tokens + 1] = {
				kind = if KEYWORDS[raw] then "kw" else "id",
				raw = raw,
				nl = pendingNl,
			}
			pendingNl = 0
			i = cursor

		else
			local matched = nil
			for _, symbol in ipairs(SYMBOLS) do
				if string.sub(source, i, i + #symbol - 1) == symbol then
					matched = symbol
					break
				end
			end
			tokens[#tokens + 1] = { kind = "sym", raw = matched or string.sub(source, i, i), nl = pendingNl }
			pendingNl = 0
			i += #(matched or string.sub(source, i, i))
		end
	end

	return tokens
end

local MERGE_HAZARDS: { [string]: boolean } = {
	["--"] = true, ["[["] = true, ["[="] = true, ["]]"] = true, ["=="] = true,
	["~="] = true, ["<="] = true, [">="] = true, ["<<"] = true, [">>"] = true,
	["+="] = true, ["-="] = true, ["*="] = true, ["/="] = true, ["//"] = true,
	["%="] = true, ["^="] = true, [".."] = true, ["::"] = true, ["??"] = true,
	["<<="] = true, [">>="] = true, ["..."] = true, ["..="] = true,
}

local function needsSeparation(a: string, b: string): boolean
	local aLast = string.sub(a, -1)
	local bFirst = string.sub(b, 1, 1)
	local wordChar = "[%w_]"
	if string.match(aLast, wordChar) and string.match(bFirst, wordChar) then
		return true
	end
	if MERGE_HAZARDS[aLast .. bFirst] then
		return true
	end

	if string.match(aLast, "%d") and bFirst == "." then
		return true
	end
	if aLast == "." and string.match(bFirst, "%d") then
		return true
	end
	return false
end

local BINARY_OPS: { [string]: boolean } = {
	["="] = true, ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true,
	["//"] = true, ["%"] = true, ["^"] = true, ["=="] = true, ["~="] = true,
	["<"] = true, [">"] = true, ["<="] = true, [">="] = true, ["<<"] = true,
	[">>"] = true, ["&"] = true, ["|"] = true, ["??"] = true, [".."] = true,
	["+="] = true, ["-="] = true, ["*="] = true, ["/="] = true, ["//="] = true,
	["%="] = true, ["^="] = true, ["<<="] = true, [">>="] = true, ["::"] = true,
	["{"] = true, ["}"] = true,
}

local NO_SPACE_BEFORE: { [string]: boolean } = {
	[")"] = true, ["]"] = true, [","] = true, [";"] = true, ["."] = true,
	[":"] = true, ["?"] = true, ["#"] = true,
}

local NO_SPACE_AFTER: { [string]: boolean } = {
	["("] = true, ["["] = true, ["."] = true, ["#"] = true, ["~"] = true,
}

local KEYWORD_SPACE_AFTER: { [string]: boolean } = {
	["if"] = true, ["while"] = true, ["for"] = true, ["return"] = true,
	["then"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
	["not"] = true, ["and"] = true, ["or"] = true, ["in"] = true,
	["repeat"] = true, ["until"] = true, ["local"] = true, ["end"] = true,
}

local CONTINUATION_PREV: { [string]: boolean } = {
	["="] = true, [","] = true, ["("] = true, ["["] = true, ["{"] = true,
	[":"] = true, ["."] = true, ["and"] = true, ["or"] = true, ["not"] = true,
	["??"] = true, ["return"] = true, ["local"] = true, ["function"] = true,
	["in"] = true, ["then"] = true, ["do"] = true, ["else"] = true,
	["elseif"] = true, ["while"] = true, ["for"] = true, ["if"] = true,
	["repeat"] = true, ["until"] = true, ["+"] = true, ["-"] = true,
	["*"] = true, ["/"] = true, ["//"] = true, ["%"] = true, ["^"] = true,
	["=="] = true, ["~="] = true, ["<"] = true, [">"] = true, ["<="] = true,
	[">="] = true, ["<<"] = true, [">>"] = true, ["&"] = true, ["|"] = true,
	[".."] = true, ["::"] = true, [":"] = true,
}

local UNARY_PREV: { [string]: boolean } = {
	["("] = true, ["["] = true, ["{"] = true, [","] = true, [";"] = true,
	["="] = true, ["=="] = true, ["~="] = true, ["<"] = true, [">"] = true,
	["<="] = true, [">="] = true, ["??"] = true, [".."] = true, ["+"] = true,
	["-"] = true, ["*"] = true, ["/"] = true, ["//"] = true, ["%"] = true,
	["^"] = true, ["&"] = true, ["|"] = true, ["<<"] = true, [">>"] = true,
	["and"] = true, ["or"] = true, ["not"] = true, ["return"] = true,
	["then"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
	["in"] = true, ["if"] = true, ["while"] = true, ["for"] = true,
	["repeat"] = true, ["until"] = true,
}

local function isUnaryPosition(prev: Token): boolean
	if prev.kind == "kw" and UNARY_PREV[prev.raw] then
		return true
	end
	return prev.kind == "sym" and UNARY_PREV[prev.raw] == true
end

local function shouldSpace(prev: Token?, cur: Token, next: Token?): boolean
	if prev == nil then
		return false
	end

	if needsSeparation(prev.raw, cur.raw) then
		return true
	end

	if cur.raw == ":" then
		return false
	end
	if prev.raw == ":" then
		if cur.kind == "id" and next and next.raw == "(" then
			return false
		end
		return true
	end

	if NO_SPACE_BEFORE[cur.raw] then
		return false
	end
	if NO_SPACE_AFTER[prev.raw] then
		return false
	end

	if KEYWORD_SPACE_AFTER[prev.raw] then
		return true
	end

	if (cur.raw == "-" or cur.raw == "+") and isUnaryPosition(prev) then
		return false
	end

	if BINARY_OPS[prev.raw] or BINARY_OPS[cur.raw] then
		return true
	end

	if cur.raw == "(" then

		return false
	end

	if cur.raw == "[" then
		local prevKind = prev.kind
		if prevKind == "id" or prevKind == "num" or prevKind == "str" then
			return false
		end
		if prev.raw == ")" or prev.raw == "]" or prev.raw == "}" then
			return false
		end
	end

	return true
end

type Block = {
	kind: "if" | "for" | "while" | "do" | "function" | "repeat",

	stmt: boolean,

	bumped: boolean,

	long: boolean?,

	inline: boolean?,
}

type Group = {
	kind: "paren" | "bracket" | "brace",

	multi: boolean,
}

local BLOCK_OPENERS: { [string]: boolean } = {
	["if"] = true, ["for"] = true, ["while"] = true, ["function"] = true,
	["repeat"] = true,
}

local function isCloser(raw: string): boolean
	return raw == "end" or raw == "until"
end

local function findBlockEnd(tokens: { Token }, i: number, seed: string, stopOnStatement: boolean): number?
	local stack: { string } = { seed }
	local parens = 0
	local STATEMENT_STARTS: { [string]: boolean } = {
		["local"] = true, ["return"] = true, ["break"] = true, ["continue"] = true,
		["while"] = true, ["for"] = true, ["repeat"] = true, ["do"] = true,
		["function"] = true, ["if"] = true,
	}
	for j = i + 1, #tokens do
		local t = tokens[j]
		if t.kind == "sym" then
			local raw = t.raw
			if raw == "(" or raw == "[" or raw == "{" then
				parens += 1
			elseif raw == ")" or raw == "]" or raw == "}" then
				parens -= 1
			elseif stopOnStatement and parens == 0 and raw == "," then
				return nil
			end
		elseif t.kind == "kw" then
			local raw = t.raw
			if stopOnStatement and parens == 0 and #stack == 1 and STATEMENT_STARTS[raw] then
				return nil
			end
			if BLOCK_OPENERS[raw] then
				stack[#stack + 1] = raw
			elseif raw == "do" then
				local top = stack[#stack]
				if top ~= "for" and top ~= "while" then
					stack[#stack + 1] = "do"
				end
			elseif raw == "end" or raw == "until" then
				stack[#stack] = nil
				if #stack == 0 then
					return j
				end
			end
		end
	end
	return nil
end

local function findFunctionEnd(tokens: { Token }, i: number): number?
	return findBlockEnd(tokens, i, "function", false)
end

local function ifHasEnd(tokens: { Token }, i: number): boolean
	return findBlockEnd(tokens, i, "if", true) ~= nil
end

local function isFunctionStatement(tokens: { Token }, i: number): boolean
	local prev = tokens[i - 1]
	if prev == nil then
		return true
	end
	local raw = prev.raw
	return raw == "local" or raw == ";" or raw == "end" or raw == "until"
		or raw == "then" or raw == "do" or raw == "else" or raw == "elseif"
end

local function findMatching(tokens: { Token }, open: number, openRaw: string): number?
	local closeRaw = if openRaw == "(" then ")" elseif openRaw == "[" then "]" else "}"
	local depth = 0
	for i = open, #tokens do
		local raw = tokens[i].raw
		if raw == openRaw then
			depth += 1
		elseif raw == closeRaw then
			depth -= 1
			if depth == 0 then
				return i
			end
		end
	end
	return nil
end

local function analyzeGroup(tokens: { Token }, open: number, close: number, options: Options): boolean
	local maxInline = options.maxInline or 72
	local maxItems = options.maxInlineItems or 6
	local length = 0
	local commas = 0
	for i = open + 1, close - 1 do
		local t = tokens[i]
		if t.kind == "comment" then

			if string.find(t.raw, "\n", 1, true) then
				return true
			end
			return true
		end
		if t.raw == "," then
			commas += 1
		end
		if t.kind == "kw" and t.raw == "function" then

			local functionEnd = findFunctionEnd(tokens, i)
			if functionEnd and (functionEnd - i) * 2 > 40 then
				return true
			end
		end
		length += #t.raw
		if length > maxInline then
			return true
		end
	end
	return commas > maxItems or length > maxInline
end

local function isStatementStart(tokens: { Token }, i: number): boolean
	local t = tokens[i]
	local raw = t.raw
	if raw == "local" or raw == "return" or raw == "break" or raw == "continue" then

		return true
	end
	if raw == "if" or raw == "for" or raw == "while" or raw == "repeat" then
		local prev = tokens[i - 1]
		if prev == nil then
			return true
		end

		return not CONTINUATION_PREV[prev.raw]
	end
	if raw == "do" then
		local prev = tokens[i - 1]
		local prevRaw = if prev then prev.raw else ""
		if prevRaw == "for" or prevRaw == "while" then
			return false
		end
		local prev = tokens[i - 1]
		if prev == nil then
			return true
		end
		return prevRaw == ";" or prevRaw == "end" or prevRaw == "until"
			or prevRaw == "then" or prevRaw == "do" or prevRaw == "else"
			or prevRaw == "elseif" or prevRaw == ")"
	end
	if raw == "function" then
		return isFunctionStatement(tokens, i)
	end
	return false
end

local function hasNewline(t: Token): boolean
	return string.find(t.raw, "\n", 1, true) ~= nil
end

function Beautifier.format(source: string, options: Options?): string
	local settings = options or {}
	local indentUnit = settings.indent or "\t"

	local tokens = tokenize(source)
	if #tokens == 0 then
		return source
	end

	local lines: { string } = {}
	local buffer: { string } = {}

	local depth = 0
	local blocks: { Block } = {}

	local groups: { { multi: boolean } } = {}
	local multiOpen = 0

	local function flushLine()
		if #buffer > 0 then
			lines[#lines + 1] = table.concat(buffer)
		end
		buffer = {}
	end

	local function emit(token: Token, spaceBefore: boolean)
		if #buffer == 0 then
			buffer[#buffer + 1] = string.rep(indentUnit, depth + multiOpen)
		elseif spaceBefore then
			buffer[#buffer + 1] = " "
		end
		buffer[#buffer + 1] = token.raw
	end

	local i = 1
	local n = #tokens
	while i <= n do
		local t = tokens[i]
		local raw = t.raw
		local prev: Token? = tokens[i - 1]
		local nextTok: Token? = tokens[i + 1]

		if t.nl > 0 then
			flushLine()

			for _, g in ipairs(groups) do
				if not g.multi then
					g.multi = true
					multiOpen += 1
				end
			end
		end

		if t.kind == "comment" then
			emit(t, #buffer > 0)
			if hasNewline(t) then

				flushLine()
			end
			i += 1
			continue
		end

		local topBlock = blocks[#blocks]
		if topBlock and not topBlock.bumped and prev then
			if (topBlock.kind == "repeat" and prev.raw == "repeat")
				or (topBlock.kind == "do" and prev.raw == "do") then
				topBlock.bumped = true
				depth += 1
			end
		end
		if raw == "end" or raw == "until" then
			local top = blocks[#blocks]
			if top then
				if top.bumped then
					depth -= 1
				end
				blocks[#blocks] = nil
			end
		elseif raw == "then" then
			local top = blocks[#blocks]
			if top and top.kind == "if" and not top.bumped then
				top.bumped = true
				depth += 1
			end
		elseif raw == "do" then
			local top = blocks[#blocks]
			if top and (top.kind == "for" or top.kind == "while") and not top.bumped then
				top.bumped = true
				depth += 1
			else

				blocks[#blocks + 1] = { kind = "do", stmt = true, bumped = false }
			end
		elseif raw == "repeat" then
			blocks[#blocks + 1] = { kind = "repeat", stmt = true, bumped = false }
		elseif raw == "if" then
			if ifHasEnd(tokens, i) then

				blocks[#blocks + 1] = { kind = "if", stmt = true, bumped = false }
			end

		elseif raw == "for" or raw == "while" then
			blocks[#blocks + 1] = { kind = raw, stmt = true, bumped = false }
		elseif raw == "function" then

			local stmt = isFunctionStatement(tokens, i)
			local longExpr = false
			if not stmt then
				local functionEnd = findFunctionEnd(tokens, i)
				longExpr = functionEnd ~= nil and (functionEnd - i) > 16
			end
			blocks[#blocks + 1] = { kind = "function", stmt = stmt, bumped = false, long = longExpr }
		elseif raw == ")" then
			local top = blocks[#blocks]
			if top and top.kind == "function" and not top.bumped and (top.stmt or top.long) then
				top.bumped = true
				depth += 1
			end
		end

		if raw == "(" or raw == "[" or raw == "{" then
			groups[#groups + 1] = { multi = false }
		elseif raw == ")" or raw == "]" or raw == "}" then
			local g = groups[#groups]
			if g and g.multi then
				multiOpen -= 1
			end
			groups[#groups] = nil
		end

		if (raw == "else" or raw == "elseif") and #buffer == 0 then
			buffer[#buffer + 1] = string.rep(indentUnit, math.max(0, depth + multiOpen - 1))
		end

		emit(t, shouldSpace(prev, t, nextTok))
		i += 1
	end

	flushLine()

	return table.concat(lines, "\n")
end

function Beautifier.stripLuauSyntax(source: string): string
	local out = source

	out = out:gsub("\239\187\191", "")

	out = out:gsub("\r\n", "\n"):gsub("\r", "\n")

	out = out:gsub("\226\128\168", "\n"):gsub("\226\128\169", "\n")

	out = out:gsub("%-%-!%a+[^\n]*", "")

	out = out:gsub("([^\n]*)", function(line)
		if line:match("^%s*export%s+type%s+") or line:match("^%s*type%s+[%a_][%w_]*%s*=") then
			return "-- " .. line
		end
		return line
	end)

	out = out:gsub("local%s+([%a_][%w_]*)%s*<[%a_][%w_]*>%s*=", "local %1 =")

	out = out:gsub("(function%s+[%a_][%w_%.:]*)%s*<[^>\n%(]+>%s*%(", "%1(")

	out = out:gsub("([%(%s,])%.%.%.%s*:%s*[%a_][%w_%.]*%??", "%1...")

	out = out:gsub("([%(%s,])([%a_][%w_]*)%s*:%s*[%a_][%w_%.]*%s*%b<>%??", "%1%2")
	out = out:gsub("([%(%s,])([%a_][%w_]*)%s*:%s*[%a_][%w_%.]*%??(%s*[%),=])", "%1%2%3")

	out = out:gsub("(%))%s*:%s*[%a_][%w_%.]*%s*%??(%s*[%),=\n]?)", function(close, trail)
		return close .. trail
	end)

	out = out:gsub("%)%s*:%s*[%a_][%w_%.]*%s*%b<>%??", ")")

	out = out:gsub("%s*::%s*[%a_][%w_%.]*%s*%b<>%??", "")
	out = out:gsub("%s*::%s*[%a_][%w_%.]*%??", "")

	return out
end

return Beautifier
