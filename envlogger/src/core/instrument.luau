local Serializer = require("./serializer")

local Instrument = {}

local CHECK_NAME = "__FUHD_CHECK__"

local BRANCH_NAME = "__FUHD_BRANCH__"

local ARG_NAME = "__FUHD_ARG__"

local BRANCH_END_NAME = "__FUHD_BRANCH_END__"

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

type Token = {
	kind: "kw" | "id" | "num" | "str" | "comment" | "sym",
	raw: string,

	start: number,
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

function Instrument.tokenize(source: string): { Token }
	local tokens: { Token } = {}
	local n = #source
	local i = 1

	while i <= n do
		local byte = string.byte(source, i)
		local start = i

		if byte == 32 or byte == 9 or byte == 10 or byte == 13 or byte == 11 or byte == 12 then
			i += 1

		elseif byte == 45 and string.sub(source, i + 1, i + 1) == "-" then

			local longRaw: string? = nil
			local longNext: number? = nil
			if string.sub(source, i + 2, i + 2) == "[" then
				longRaw, longNext = readLongBracket(source, i + 2)
			end
			if longRaw and longNext then
				tokens[#tokens + 1] = { kind = "comment", raw = "--" .. longRaw, start = start }
				i = longNext
			else
				local endAt = string.find(source, "\n", i, true) or (n + 1)
				tokens[#tokens + 1] = {
					kind = "comment",
					raw = string.sub(source, i, endAt - 1) .. (if endAt <= n then "\n" else ""),
					start = start,
				}
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
			tokens[#tokens + 1] = { kind = "str", raw = string.sub(source, i, math.min(cursor, n)), start = start }
			i = math.min(cursor, n) + 1

		elseif byte == 91 then
			local raw, nextAt = readLongBracket(source, i)
			if raw then
				tokens[#tokens + 1] = { kind = "str", raw = raw, start = start }
				i = nextAt
			else
				tokens[#tokens + 1] = { kind = "sym", raw = "[", start = start }
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
			tokens[#tokens + 1] = { kind = "str", raw = string.sub(source, i, math.min(cursor, n)), start = start }
			i = math.min(cursor, n) + 1

		elseif isDigit(byte) or (byte == 46 and isDigit(string.byte(source, i + 1) or 0)) then
			local cursor = i
			local function isHexDigit(b: number): boolean
				return (b >= 48 and b <= 57) or (b >= 65 and b <= 70) or (b >= 97 and b <= 102)
			end
			local function isBinDigit(b: number): boolean
				return b == 48 or b == 49
			end

			if string.sub(source, i, i + 1) == "0x" or string.sub(source, i, i + 1) == "0X" then
				cursor += 2
				while true do
					local b = string.byte(source, cursor) or 0
					if isHexDigit(b) then
						cursor += 1
					elseif b == 95 then

						local j = cursor
						while string.byte(source, j) == 95 do
							j += 1
						end
						if isHexDigit(string.byte(source, j) or 0) then
							cursor = j
						else
							break
						end
					else
						break
					end
				end

				while string.byte(source, cursor) == 95 do
					cursor += 1
				end
			elseif string.sub(source, i, i + 1) == "0b" or string.sub(source, i, i + 1) == "0B" then
				cursor += 2
				while true do
					local b = string.byte(source, cursor) or 0
					if isBinDigit(b) then
						cursor += 1
					elseif b == 95 then
						local j = cursor
						while string.byte(source, j) == 95 do
							j += 1
						end
						if isBinDigit(string.byte(source, j) or 0) then
							cursor = j
						else
							break
						end
					else
						break
					end
				end
				while string.byte(source, cursor) == 95 do
					cursor += 1
				end
			else
				while true do
					local b = string.byte(source, cursor) or 0
					if isDigit(b) then
						cursor += 1
					elseif b == 95 then
						local j = cursor
						while string.byte(source, j) == 95 do
							j += 1
						end
						if isDigit(string.byte(source, j) or 0) then
							cursor = j
						else
							break
						end
					else
						break
					end
				end
				if string.sub(source, cursor, cursor) == "." then
					cursor += 1
					while true do
						local b = string.byte(source, cursor) or 0
						if isDigit(b) then
							cursor += 1
						elseif b == 95 then
							local j = cursor
							while string.byte(source, j) == 95 do
								j += 1
							end
							if isDigit(string.byte(source, j) or 0) then
								cursor = j
							else
								break
							end
						else
							break
						end
					end
				end
				local exponent = string.sub(source, cursor, cursor)
				if exponent == "e" or exponent == "E" then
					local after = cursor + 1
					local sign = string.sub(source, after, after)
					if sign == "+" or sign == "-" then
						after += 1
					end
					local b0 = string.byte(source, after) or 0
					if isDigit(b0) or b0 == 95 then
						cursor = after
						while true do
							local b = string.byte(source, cursor) or 0
							if isDigit(b) then
								cursor += 1
							elseif b == 95 then
								local j = cursor
								while string.byte(source, j) == 95 do
									j += 1
								end
								if isDigit(string.byte(source, j) or 0) then
									cursor = j
								else
									break
								end
							else
								break
							end
						end
					end
				end
				while string.byte(source, cursor) == 95 do
					cursor += 1
				end
			end
			tokens[#tokens + 1] = { kind = "num", raw = string.sub(source, i, cursor - 1), start = start }
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
				start = start,
			}
			i = cursor

		else
			local matched: string? = nil
			for _, symbol in ipairs(SYMBOLS) do
				if string.sub(source, i, i + #symbol - 1) == symbol then
					matched = symbol
					break
				end
			end
			if matched then
				tokens[#tokens + 1] = { kind = "sym", raw = matched, start = start }
				i += #matched
			else

				i += 1
			end
		end
	end

	return tokens
end

local function matchParen(tokens: { Token }, open: number): number?
	local depth = 0
	for i = open, #tokens do
		local raw = tokens[i].raw
		if raw == "(" then
			depth += 1
		elseif raw == ")" then
			depth -= 1
			if depth == 0 then
				return i
			end
		end
	end
	return nil
end

local function bodyStartOf(tokens: { Token }, k: number): number?
	local raw = tokens[k].raw

	if raw == "repeat" then
		return k + 1
	end

	if raw == "function" then

		local open: number? = nil
		for i = k + 1, #tokens do
			if tokens[i].raw == "(" then
				open = i
				break
			end
		end
		if not open then
			return nil
		end
		local close = matchParen(tokens, open)
		if not close then
			return nil
		end
		local after = close + 1
		if after <= #tokens and tokens[after].raw == ":" then

			local depth = 0
			for i = after, #tokens do
				local r = tokens[i].raw
				if r == "(" or r == "{" or r == "[" then
					depth += 1
				elseif r == ")" or r == "}" or r == "]" then
					depth -= 1
					if depth <= 0 then
						return i + 1
					end
				end
			end
			return nil
		end
		return after
	end

	local depth = 0
	for i = k + 1, #tokens do
		local r = tokens[i].raw
		if r == "(" then
			depth += 1
		elseif r == ")" then
			depth -= 1
		elseif r == "do" and depth == 0 then
			return i + 1
		end
	end
	return nil
end

local MAX_SOURCE_BYTES = 8000000
local MAX_TOKENS = 1500000

local LOCAL_NAME = "__FUHD_LOCAL__"

type Edit = {
	start: number,
	finish: number,
	text: string,

	prefix: string?,
	initText: string?,
	suffix: string?,

	syntheticSpans: { { start: number, finish: number } }?,
}

local CONSTANT_FOR_MAX_ITERATIONS = 8192
local function constantSmallFor(tokens: { Token }, k: number): boolean
	if tokens[k].raw ~= "for" then
		return false
	end
	local j = k + 1

	while j <= #tokens and tokens[j].kind == "id" do
		j += 1
	end
	if j > #tokens or tokens[j].raw ~= "=" then
		return false
	end
	j += 1

	local bounds: { number } = {}
	while j <= #tokens do
		local t = tokens[j]
		if t.kind == "num" then
			local value = tonumber(t.raw)
			if value == nil or value ~= value then
				return false
			end
			bounds[#bounds + 1] = value
			j += 1
		elseif t.raw == "," then
			j += 1
		elseif t.raw == "do" and #bounds >= 2 and #bounds <= 3 then
			local start = bounds[1]
			local finish = bounds[2]
			local step = bounds[3] or 1
			if step == 0 or step ~= step then
				return false
			end
			local iterations = (finish - start) / step + 1
			return iterations >= 0 and iterations <= CONSTANT_FOR_MAX_ITERATIONS
		else
			return false
		end
	end
	return false
end

local function numericForVariable(tokens: { Token }, k: number): string?
	if tokens[k].raw ~= "for" then
		return nil
	end
	local j = k + 1
	if j > #tokens or tokens[j].kind ~= "id" then
		return nil
	end
	local name = tokens[j].raw
	local after = j + 1
	if after <= #tokens and tokens[after].raw == "=" then
		return name
	end
	return nil
end

local FOR_STRIDE = 256
local function loopCheckText(tokens: { Token }, k: number): string
	local var = numericForVariable(tokens, k)
	if var then

		return string.format("if %s %% %d == 0 then %s() end ", var, FOR_STRIDE, CHECK_NAME)
	end
	return CHECK_NAME .. "();"
end

local function collectLoopInserts(tokens: { Token }): { Edit }
	local edits: { Edit } = {}
	local seen: { [number]: boolean } = {}

	for i = 1, #tokens do
		local raw = tokens[i].raw
		if raw == "while" or raw == "for" or raw == "repeat" or raw == "function" then
			if raw == "for" and constantSmallFor(tokens, i) then

				continue
			end
			local body = bodyStartOf(tokens, i)
			if body and body <= #tokens then
				local offset = tokens[body].start
				if offset and not seen[offset] then
					seen[offset] = true
					edits[#edits + 1] = { start = offset, finish = offset - 1, text = loopCheckText(tokens, i) }
				end
			end
		end
	end
	return edits
end

local CONTINUES_EXPR: { [string]: boolean } = {
	["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["//"] = true,
	["%"] = true, ["^"] = true, [".."] = true, ["=="] = true, ["~="] = true,
	["<="] = true, [">="] = true, ["<"] = true, [">"] = true, ["and"] = true,
	["or"] = true, ["&"] = true, ["|"] = true, ["~"] = true, ["<<"] = true,
	[">>"] = true, ["??"] = true, ["."] = true, [":"] = true, ["?"] = true,
	["not"] = true, ["#"] = true,
}

local function collectLocalEdits(source: string, tokens: { Token }): { Edit }
	local edits: { Edit } = {}

	for i = 1, #tokens do
		if tokens[i].raw ~= "local" then
			continue
		end

		local j = i + 1
		local name: string? = nil
		local multi = false
		while j <= #tokens do
			local raw = tokens[j].raw
			if raw == "=" then
				break
			elseif raw == "," then
				multi = true
				break
			elseif raw == "<" then

				while j <= #tokens and tokens[j].raw ~= ">" do
					j += 1
				end
			elseif tokens[j].kind == "id" then
				if name == nil then
					name = raw
				else
					multi = true
					break
				end
			else
				multi = true
				break
			end
			j += 1
		end
		if multi or name == nil or j > #tokens or tokens[j].raw ~= "=" then
			continue
		end

		local start = j + 1
		local depth = 0
		local pendingEnd = 0
		local expectOperand = false
		local k = start
		while k <= #tokens do
			local raw = tokens[k].raw
			if pendingEnd > 0 then
				if raw == "function" then
					pendingEnd += 1
				elseif raw == "end" then
					pendingEnd -= 1
				end
				k += 1
				continue
			end
			if raw == "(" or raw == "{" or raw == "[" then
				depth += 1
			elseif raw == ")" or raw == "}" or raw == "]" then
				depth -= 1
				if depth < 0 then
					break
				end
				expectOperand = false
			elseif raw == "function" then

				if depth > 0 or k == start or expectOperand then
					pendingEnd = 1
					expectOperand = false
				else
					break
				end
			elseif depth == 0 then
				if k == start then

					expectOperand = CONTINUES_EXPR[raw] == true
				elseif expectOperand then
					expectOperand = false
				elseif CONTINUES_EXPR[raw] then
					expectOperand = true
				else
					break
				end
			end
			k += 1
		end
		if k <= start then
			continue
		end

		local last = tokens[k - 1]
		local finish = last.start + #last.raw - 1
		local initText = string.sub(source, tokens[start].start, finish)
		edits[#edits + 1] = {
			start = tokens[start].start,
			finish = finish,
			prefix = string.format('%s("%s", ', LOCAL_NAME, name),
			initText = initText,
			suffix = ")",
		}
	end

	return edits
end

local EXPRESSION_PREV: { [string]: boolean } = {
	["("] = true, ["["] = true, ["{"] = true, ["="] = true, [","] = true,
	[":"] = true, ["."] = true, ["return"] = true, ["not"] = true,
	["and"] = true, ["or"] = true, ["??"] = true,
	["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["//"] = true,
	["%"] = true, ["^"] = true, ["=="] = true, ["~="] = true, ["<"] = true,
	[">"] = true, ["<="] = true, [">="] = true, ["<<"] = true, [">>"] = true,
	["&"] = true, ["|"] = true, [".."] = true, ["::"] = true,
}

local function isStatementIf(tokens: { Token }, i: number): boolean
	local prev = tokens[i - 1]
	if prev == nil or prev.kind == "comment" then
		return true
	end
	return EXPRESSION_PREV[prev.raw] ~= true
end

local function findIfChainEnd(tokens: { Token }, i: number): number?
	local stack: { { kind: string, header: boolean? } } = { { kind = "if" } }
	local budget = 20000
	for j = i + 1, #tokens do
		budget -= 1
		if budget <= 0 then
			return nil
		end
		local t = tokens[j]
		if t.kind ~= "kw" then
			continue
		end
		local raw = t.raw
		if raw == "if" or raw == "function" or raw == "repeat" then
			stack[#stack + 1] = { kind = raw }
		elseif raw == "for" or raw == "while" then
			stack[#stack + 1] = { kind = raw, header = true }
		elseif raw == "do" then
			local top = stack[#stack]
			if top and (top.kind == "for" or top.kind == "while") and top.header then

				top.header = false
			else
				stack[#stack + 1] = { kind = "do" }
			end
		elseif raw == "until" then
			if stack[#stack] and stack[#stack].kind == "repeat" then
				stack[#stack] = nil
			end
		elseif raw == "end" then
			stack[#stack] = nil
			if #stack == 0 then
				return j
			end
		end
	end
	return nil
end

local function isStateMachineChain(tokens: { Token }, startIdx: number): boolean
	if not isStatementIf(tokens, startIdx) then
		return false
	end
	local endAt = findIfChainEnd(tokens, startIdx)
	if not endAt then
		return false
	end
	local depth = 0
	local branchCount = 0
	local vars: { [string]: number } = {}
	for i = startIdx, endAt do
		local raw = tokens[i].raw
		if raw == "if" or raw == "function" or raw == "repeat" then
			depth += 1
		elseif raw == "end" then
			depth -= 1
		elseif (raw == "if" or raw == "elseif") and depth == 1 then
			branchCount += 1
			local cd = 0
			for j = i + 1, #tokens do
				local r = tokens[j].raw
				if r == "then" and cd == 0 then break end
				if r == "(" or r == "{" or r == "[" then cd += 1
				elseif r == ")" or r == "}" or r == "]" then cd -= 1
				end
				if cd == 0 and j > i + 1 then
					local prev = tokens[j - 1]
					local op = r
					local isComp = (op == "<" or op == "<=" or op == ">" or op == ">=" or op == "==" or op == "~=")
					if isComp and prev.kind == "id" and not KEYWORDS[prev.raw] then
						local nxt = tokens[j + 1]
						if nxt and nxt.kind == "num" then
							vars[prev.raw] = (vars[prev.raw] or 0) + 1
						elseif nxt and nxt.raw == "-" and tokens[j + 2] and tokens[j + 2].kind == "num" then
							vars[prev.raw] = (vars[prev.raw] or 0) + 1
						end
					end
				end
			end
		end
	end
	if branchCount < 5 then
		return false
	end
	local maxCount = 0
	for _, count in pairs(vars) do
		if count > maxCount then maxCount = count end
	end
	return maxCount >= 5 and maxCount >= math.floor(branchCount * 0.6)
end

local function collectBranchEndEdits(tokens: { Token }): { Edit }
	local edits: { Edit } = {}
	for i = 1, #tokens do
		local t = tokens[i]
		if t.kind ~= "kw" or t.raw ~= "if" or not isStatementIf(tokens, i) then
			continue
		end

		if isStateMachineChain(tokens, i) then continue end
		local endAt = findIfChainEnd(tokens, i)
		if endAt then
			local at = tokens[endAt].start + #tokens[endAt].raw
			edits[#edits + 1] = {
				start = at,
				finish = at - 1,
				text = " " .. BRANCH_END_NAME .. "();",
			}
		end
	end
	return edits
end

local function collectElseEdits(tokens: { Token }): { Edit }
	local edits: { Edit } = {}
	for i = 1, #tokens do
		local t = tokens[i]
		if t.kind ~= "kw" or t.raw ~= "if" or not isStatementIf(tokens, i) then
			continue
		end

		if isStateMachineChain(tokens, i) then continue end
		local endAt = findIfChainEnd(tokens, i)
		if not endAt then
			continue
		end

		local stack: { { kind: string, header: boolean? } } = { { kind = "if" } }
		local nextId = 100000 + i
		for j = i + 1, endAt - 1 do
			local tt = tokens[j]
			if tt.kind ~= "kw" then
				continue
			end
			local raw = tt.raw
			if raw == "if" or raw == "function" or raw == "repeat" then
				stack[#stack + 1] = { kind = raw }
			elseif raw == "for" or raw == "while" then
				stack[#stack + 1] = { kind = raw, header = true }
			elseif raw == "do" then
				local top = stack[#stack]
				if top and (top.kind == "for" or top.kind == "while") and top.header then
					top.header = false
				else
					stack[#stack + 1] = { kind = "do" }
				end
			elseif raw == "until" then
				if stack[#stack] and stack[#stack].kind == "repeat" then
					stack[#stack] = nil
				end
			elseif raw == "end" then
				stack[#stack] = nil
			elseif raw == "else" and #stack == 1 then

				local at = tt.start + #tt.raw
				edits[#edits + 1] = {
					start = at,
					finish = at - 1,
					text = string.format(" %s(%d, \"\", \"else\", true, 0);", BRANCH_NAME, nextId),
				}
			end
		end
	end
	return edits
end

local function collectBranchEdits(source: string, tokens: { Token }): { Edit }
	local edits: { Edit } = {}
	local nextId = 1

	local skip: { [number]: boolean } = {}
	do
		local j = 1
		while j <= #tokens do
			if tokens[j].raw == "if" and not skip[j] and isStateMachineChain(tokens, j) then
				local endAt = findIfChainEnd(tokens, j)
				if endAt then
					for k = j, endAt do
						skip[k] = true
					end
					j = endAt + 1
					continue
				end
			end
			j += 1
		end
	end

	for i = 1, #tokens do
		if skip[i] then continue end
		local raw = tokens[i].raw
		if raw ~= "if" and raw ~= "elseif" then
			continue
		end

		local depth = 0
		local thenAt: number? = nil
		for j = i + 1, #tokens do
			local r = tokens[j].raw
			if r == "(" or r == "{" or r == "[" then
				depth += 1
			elseif r == ")" or r == "}" or r == "]" then
				depth -= 1
				if depth < 0 then
					break
				end
			elseif r == "then" and depth == 0 then
				thenAt = j
				break
			end
		end
		if not thenAt or thenAt <= i + 1 then
			continue
		end

		local condStart = tokens[i + 1].start
		local condToken = tokens[thenAt - 1]
		local condFinish = condToken.start + #condToken.raw - 1
		local condText = string.sub(source, condStart, condFinish)

		edits[#edits + 1] = {
			start = condStart,
			finish = condFinish,
			prefix = string.format(
				"%s(%d, %s, %s, ",
				BRANCH_NAME,
				nextId,
				Serializer.stringLiteral(condText),
				Serializer.stringLiteral(raw)
			),
			initText = condText,

			suffix = ", " .. (if raw == "if" and isStatementIf(tokens, i) then "1" else "0") .. ")",
		}
		nextId += 1
	end

	return edits
end

local OUTPUT_FUNCTIONS: { [string]: boolean } = {
	print = true,
	warn = true,
	error = true,
	assert = true,
}

local function collectArgEdits(source: string, tokens: { Token }): { Edit }
	local edits: { Edit } = {}

	for i = 1, #tokens do
		if tokens[i].kind ~= "id" or not OUTPUT_FUNCTIONS[tokens[i].raw] then
			continue
		end

		local prev = tokens[i - 1]
		if prev and (prev.raw == "." or prev.raw == ":") then
			continue
		end
		local open = i + 1
		if open > #tokens or tokens[open].raw ~= "(" then
			continue
		end
		local close = matchParen(tokens, open)
		if not close or close <= open + 1 then
			continue
		end

		local depth = 0
		local argStart: number? = nil
		local j = open + 1
		while j <= close - 1 do
			local r = tokens[j].raw
			if r == "(" or r == "{" or r == "[" then
				depth += 1
			elseif r == ")" or r == "}" or r == "]" then
				depth -= 1
			elseif r == "," and depth == 0 then
				if argStart then
					if j - 1 == argStart and tokens[argStart].kind == "id" then
						local name = tokens[argStart].raw
						local finish = tokens[argStart].start + #name - 1
						edits[#edits + 1] = {
							start = tokens[argStart].start,
							finish = finish,
							text = string.format('%s("%s", %s)', ARG_NAME, name, name),
						}
					end
					argStart = nil
				end
			elseif argStart == nil then
				argStart = j
			end
			j += 1
		end

		if argStart then
			if close - 1 == argStart and tokens[argStart].kind == "id" then
				local name = tokens[argStart].raw
				local finish = tokens[argStart].start + #name - 1
				edits[#edits + 1] = {
					start = tokens[argStart].start,
					finish = finish,
					text = string.format('%s("%s", %s)', ARG_NAME, name, name),
				}
			end
		end
	end

	return edits
end

local OP_NAME = "__FUHD_OP__"

local COMPARISON_OPS: { [string]: string } = {
	["=="] = "eq",
	["~="] = "ne",
	["<"] = "lt",
	["<="] = "le",
	[">"] = "gt",
	[">="] = "ge",
}

local OP_BOUNDARY: { [string]: boolean } = {
	["and"] = true, ["or"] = true,
	["=="] = true, ["~="] = true, ["<"] = true, [">"] = true,
	["<="] = true, [">="] = true,
	[","] = true, [";"] = true, ["="] = true,
	["+="] = true, ["-="] = true, ["*="] = true, ["/="] = true,
	["%="] = true, ["^="] = true, ["..="] = true,
	["<<="] = true, [">>="] = true,
	["then"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
	["end"] = true, ["return"] = true, ["until"] = true, ["if"] = true,
	["while"] = true, ["for"] = true, ["repeat"] = true, ["in"] = true,
	["local"] = true, ["break"] = true, ["continue"] = true,
	["function"] = true, ["?"] = true,

	["??"] = true,

	["->"] = true, ["=>"] = true, ["&"] = true, ["|"] = true,
	["<<"] = true, [">>"] = true, ["!"] = true, ["@"] = true,
}

local function isMethodColon(tokens: { Token }, i: number): boolean
	local nxt = tokens[i + 1]
	if nxt == nil or nxt.kind ~= "id" then
		return false
	end
	local after = tokens[i + 2]
	if after == nil then
		return false
	end
	return after.raw == "(" or after.raw == "{" or after.kind == "str"
end

local function leftOperandStart(tokens: { Token }, k: number): (number?, boolean)
	local depth = 0
	local first: number? = nil
	local i = k - 1
	while i >= 1 do
		local t = tokens[i]
		local raw = t.raw
		if t.kind == "comment" then
			i -= 1
			continue
		end

		if raw == "::" then
			return nil, true
		end
		if raw == ":" and not isMethodColon(tokens, i) then
			return nil, true
		end
		if raw == ")" or raw == "]" or raw == "}" then
			depth += 1
		elseif raw == "(" or raw == "[" or raw == "{" then
			depth -= 1
			if depth < 0 then
				break
			end
		elseif depth == 0 and OP_BOUNDARY[raw] then
			break
		end
		first = i
		i -= 1
	end
	return first, false
end

local function rightOperandFinish(tokens: { Token }, k: number): (number?, boolean)
	local depth = 0
	local last: number? = nil
	local i = k + 1
	while i <= #tokens do
		local t = tokens[i]
		local raw = t.raw
		if t.kind == "comment" then
			i += 1
			continue
		end
		if raw == "::" then
			return nil, true
		end
		if raw == ":" and not isMethodColon(tokens, i) then
			return nil, true
		end
		if raw == "(" or raw == "[" or raw == "{" then
			depth += 1
		elseif raw == ")" or raw == "]" or raw == "}" then
			depth -= 1
			if depth < 0 then
				break
			end
		elseif depth == 0 and OP_BOUNDARY[raw] then
			break
		end
		last = i
		i += 1
	end
	return last, false
end

local ANGLE_STOP: { [string]: boolean } = {
	["("] = true, [")"] = true, ["{"] = true, ["}"] = true,
	[";"] = true, ["then"] = true, ["do"] = true, ["end"] = true,
	["local"] = true, ["return"] = true, ["if"] = true, ["while"] = true,
	["repeat"] = true, ["until"] = true, ["else"] = true, ["elseif"] = true,
}

local function collectAngleSkips(tokens: { Token }): { [number]: boolean }
	local skip: { [number]: boolean } = {}

	local function markFrom(open: number)
		local depth = 0
		local i = open
		while i <= #tokens do
			local raw = tokens[i].raw
			if raw == "<" then
				depth += 1
			elseif raw == ">" then
				depth -= 1
				if depth == 0 then
					for m = open, i do
						skip[m] = true
					end
					return
				end
			elseif raw == ">>" then

				depth -= 2
				if depth <= 0 then
					for m = open, i do
						skip[m] = true
					end
					return
				end
			elseif ANGLE_STOP[raw] or raw == "=" then
				return
			end
			i += 1
		end
	end

	for i = 1, #tokens do
		local raw = tokens[i].raw
		if raw == "local" or raw == "function" or raw == "type" then

			local j = i + 1
			while j <= #tokens do
				local r = tokens[j].raw
				if tokens[j].kind == "id" or r == "." or r == ":" then
					j += 1
				else
					break
				end
			end
			if j <= #tokens and tokens[j].raw == "<" then
				markFrom(j)
			end
		elseif raw == ":" and not isMethodColon(tokens, i) then

			local j = i + 1
			while j <= #tokens do
				local r = tokens[j].raw
				if tokens[j].kind == "id" or r == "." then
					j += 1
				else
					break
				end
			end
			if j <= #tokens and tokens[j].raw == "<" then
				markFrom(j)
			end
		end
	end

	return skip
end

local function collectOpEdits(
	source: string,
	tokens: { Token },
	synthetic: { { start: number, finish: number } }
): { Edit }

	local regionAt = 1
	local function isSynthetic(offset: number): boolean
		while regionAt <= #synthetic and synthetic[regionAt].finish < offset do
			regionAt += 1
		end
		local region = synthetic[regionAt]
		return region ~= nil and offset >= region.start
	end

	local skip: { [number]: boolean } = collectAngleSkips(tokens)
	do
		local j = 1
		while j <= #tokens do
			if tokens[j].raw == "if" and not skip[j] and isStateMachineChain(tokens, j) then
				local endAt = findIfChainEnd(tokens, j)
				if endAt then
					for m = j, endAt do
						skip[m] = true
					end
					j = endAt + 1
					continue
				end
			end
			j += 1
		end
	end

	local candidates: { Edit } = {}
	for k = 1, #tokens do
		local token = tokens[k]
		if token.kind ~= "sym" then
			continue
		end
		local opcode = COMPARISON_OPS[token.raw]
		if opcode == nil or skip[k] then
			continue
		end
		if isSynthetic(token.start) then
			continue
		end

		local firstIdx, leftTyped = leftOperandStart(tokens, k)
		if leftTyped or firstIdx == nil then
			continue
		end
		local lastIdx, rightTyped = rightOperandFinish(tokens, k)
		if rightTyped or lastIdx == nil then
			continue
		end

		local spanStart = tokens[firstIdx].start
		local opStart = token.start
		local opFinish = opStart + #token.raw - 1
		local lastToken = tokens[lastIdx]
		local spanFinish = lastToken.start + #lastToken.raw - 1
		if spanStart >= opStart or spanFinish <= opFinish then
			continue
		end

		local leftText = string.sub(source, spanStart, opStart - 1)
		local rightText = string.sub(source, opFinish + 1, spanFinish)
		if #leftText == 0 or #rightText == 0 then
			continue
		end

		candidates[#candidates + 1] = {
			start = spanStart,
			finish = spanFinish,
			text = string.format(
				"%s(%s, %s, %s)",
				OP_NAME,
				Serializer.stringLiteral(opcode),
				leftText,
				rightText
			),
		}
	end

	table.sort(candidates, function(a, b)
		if a.start ~= b.start then
			return a.start < b.start
		end
		return a.finish > b.finish
	end)
	local kept: { Edit } = {}
	local lastFinish = 0
	for _, candidate in ipairs(candidates) do
		if candidate.start > lastFinish then
			kept[#kept + 1] = candidate
			lastFinish = candidate.finish
		end
	end
	return kept
end

local function applyEdits(source: string, edits: { Edit }): (string, { { start: number, finish: number } })
	if #edits == 0 then
		return source, {}
	end
	table.sort(edits, function(a, b)
		if a.start ~= b.start then
			return a.start < b.start
		end
		return a.finish < b.finish
	end)
	local pieces: { string } = {}
	local regions: { { start: number, finish: number } } = {}
	local cursor = 1

	local written = 0
	for _, edit in ipairs(edits) do
		local copied = string.sub(source, cursor, edit.start - 1)
		pieces[#pieces + 1] = copied
		written += #copied

		if string.match(string.sub(edit.text, 1, 1), "[%w_]") then
			local prevChar = ""
			for idx = #pieces, 1, -1 do
				local piece = pieces[idx]
				if #piece > 0 then
					prevChar = string.sub(piece, -1)
					break
				end
			end
			if string.match(prevChar, "[%w_]") then
				pieces[#pieces + 1] = " "
				written += 1
			end
		end
		pieces[#pieces + 1] = edit.text
		local spans = edit.syntheticSpans
		if spans == nil then
			if #edit.text > 0 then
				regions[#regions + 1] = { start = written + 1, finish = written + #edit.text }
			end
		else
			for _, span in ipairs(spans) do
				if span.finish >= span.start then
					regions[#regions + 1] = {
						start = written + span.start,
						finish = written + span.finish,
					}
				end
			end
		end
		written += #edit.text

		cursor = if edit.finish < edit.start then edit.start else edit.finish + 1
	end
	pieces[#pieces + 1] = string.sub(source, cursor)
	return table.concat(pieces), regions
end

export type ApplyOptions = {

	operators: boolean?,
}

function Instrument.apply(source: string, options: ApplyOptions?): string?
	if #source == 0 or #source > MAX_SOURCE_BYTES then
		return nil
	end

	local first = string.byte(source, 1)
	if first and first < 0x20 then
		return nil
	end

	local tokens = Instrument.tokenize(source)
	if #tokens == 0 or #tokens > MAX_TOKENS then
		return nil
	end

	local loopInserts = collectLoopInserts(tokens)
	local localEdits = collectLocalEdits(source, tokens)
	local branchEdits = collectBranchEdits(source, tokens)
	local branchEndEdits = collectBranchEndEdits(tokens)
	local elseEdits = collectElseEdits(tokens)
	local argEdits = collectArgEdits(source, tokens)

	local plain: { Edit } = {}
	for _, insert in ipairs(loopInserts) do
		plain[#plain + 1] = insert
	end
	for _, insert in ipairs(argEdits) do
		plain[#plain + 1] = insert
	end

	for _, insert in ipairs(branchEndEdits) do
		local insideLocal = false
		for _, localEdit in ipairs(localEdits) do
			if insert.start > localEdit.start and insert.start <= localEdit.finish then
				insideLocal = true
				break
			end
		end
		if not insideLocal then
			plain[#plain + 1] = insert
		end
	end
	for _, insert in ipairs(elseEdits) do
		local insideLocal = false
		for _, localEdit in ipairs(localEdits) do
			if insert.start > localEdit.start and insert.start <= localEdit.finish then
				insideLocal = true
				break
			end
		end
		if not insideLocal then
			plain[#plain + 1] = insert
		end
	end

	local keptBranches: { Edit } = {}
	for _, branch in ipairs(branchEdits) do
		local insideLocal = false
		for _, localEdit in ipairs(localEdits) do
			if branch.start > localEdit.start and branch.start <= localEdit.finish then
				insideLocal = true
				break
			end
		end
		if not insideLocal then
			keptBranches[#keptBranches + 1] = branch
		end
	end

	local wraps: { Edit } = {}
	for _, edit in ipairs(localEdits) do
		wraps[#wraps + 1] = edit
	end
	for _, edit in ipairs(keptBranches) do
		wraps[#wraps + 1] = edit
	end

	local merged: { Edit } = {}
	local used: { [number]: boolean } = {}
	for _, edit in ipairs(wraps) do
		local inner: { Edit } = {}
		for idx, insert in ipairs(plain) do
			if insert.start > edit.start and insert.start <= edit.finish then
				inner[#inner + 1] = insert
				used[idx] = true
			end
		end
		local text: string

		local spans: { { start: number, finish: number } } = {}
		local prefix = edit.prefix :: string
		local suffix = edit.suffix :: string
		local initText = edit.initText :: string
		if #prefix > 0 then
			spans[#spans + 1] = { start = 1, finish = #prefix }
		end
		if #inner == 0 then
			text = prefix .. initText .. suffix
			if #suffix > 0 then
				spans[#spans + 1] = {
					start = #prefix + #initText + 1,
					finish = #prefix + #initText + #suffix,
				}
			end
		else
			table.sort(inner, function(a, b)
				return a.start < b.start
			end)
			local pieces: { string } = { prefix }
			local written = #prefix
			local cursor = 0
			for _, insert in ipairs(inner) do
				local rel = insert.start - edit.start
				local copied = string.sub(initText, cursor + 1, rel)
				pieces[#pieces + 1] = copied
				written += #copied
				pieces[#pieces + 1] = insert.text
				if #insert.text > 0 then
					spans[#spans + 1] = { start = written + 1, finish = written + #insert.text }
				end
				written += #insert.text
				cursor = rel
			end
			local tail = string.sub(initText, cursor + 1)
			pieces[#pieces + 1] = tail
			written += #tail
			pieces[#pieces + 1] = suffix
			if #suffix > 0 then
				spans[#spans + 1] = { start = written + 1, finish = written + #suffix }
			end
			text = table.concat(pieces)
		end
		merged[#merged + 1] = {
			start = edit.start,
			finish = edit.finish,
			text = text,
			syntheticSpans = spans,
		}
	end
	for idx, insert in ipairs(plain) do
		if not used[idx] then
			merged[#merged + 1] = insert
		end
	end

	if #merged > 0 then
		local names: { [string]: boolean } = {}
		for _, edit in ipairs(merged) do
			if string.find(edit.text, CHECK_NAME, 1, true) then
				names[CHECK_NAME] = true
			end
			if string.find(edit.text, LOCAL_NAME, 1, true) then
				names[LOCAL_NAME] = true
			end
			if string.find(edit.text, BRANCH_NAME, 1, true) then
				names[BRANCH_NAME] = true
			end
			if string.find(edit.text, BRANCH_END_NAME, 1, true) then
				names[BRANCH_END_NAME] = true
			end
			if string.find(edit.text, ARG_NAME, 1, true) then
				names[ARG_NAME] = true
			end
		end
		local bindings: { string } = {}
		for name in pairs(names) do
			bindings[#bindings + 1] = "local " .. name .. " = " .. name
		end
		if #bindings > 0 then
			table.sort(bindings)
			merged[#merged + 1] = { start = 1, finish = 0, text = table.concat(bindings, ";") .. ";" }
		end
	end

	local wantOperators = if options and options.operators ~= nil
		then options.operators == true
		else true

	local instrumented: string
	local synthetic: { { start: number, finish: number } }
	if #merged == 0 then

		if not wantOperators then
			return nil
		end
		instrumented, synthetic = source, {}
	else
		instrumented, synthetic = applyEdits(source, merged)
	end

	if not wantOperators then
		return instrumented
	end

	local rewritten = Instrument.applyOperators(instrumented, synthetic)
	if rewritten ~= nil then
		return rewritten
	end

	return if #merged == 0 then nil else instrumented
end

function Instrument.applyOperators(
	source: string,
	synthetic: { { start: number, finish: number } }?
): string?
	if #source == 0 or #source > MAX_SOURCE_BYTES then
		return nil
	end
	local first = string.byte(source, 1)
	if first and first < 0x20 then
		return nil
	end
	local tokens = Instrument.tokenize(source)
	if #tokens == 0 or #tokens > MAX_TOKENS then
		return nil
	end

	local edits = collectOpEdits(source, tokens, synthetic or {})
	if #edits == 0 then
		return nil
	end

	edits[#edits + 1] = {
		start = 1,
		finish = 0,
		text = "local " .. OP_NAME .. " = " .. OP_NAME .. ";",
	}
	local rewritten = applyEdits(source, edits)
	return rewritten
end

function Instrument.applyLoops(source: string): string?
	if #source == 0 or #source > MAX_SOURCE_BYTES then
		return nil
	end
	local first = string.byte(source, 1)
	if first and first < 0x20 then
		return nil
	end
	local tokens = Instrument.tokenize(source)
	if #tokens == 0 or #tokens > MAX_TOKENS then
		return nil
	end
	local loopInserts = collectLoopInserts(tokens)
	if #loopInserts == 0 then
		return nil
	end

	loopInserts[#loopInserts + 1] = {
		start = 1,
		finish = 0,
		text = "local " .. CHECK_NAME .. " = " .. CHECK_NAME .. ";",
	}

	return (applyEdits(source, loopInserts))
end

local BITWISE_BINARY_FN: { [string]: string } = {
	["<<"] = "lshift", [">>"] = "rshift", ["&"] = "band", ["~"] = "bxor", ["|"] = "bor",
}
local BITWISE_RANK: { [string]: number } = {
	["<<"] = 5, [">>"] = 5, ["&"] = 4, ["~"] = 3, ["|"] = 2,
}
local BITWISE_SYM: { [string]: boolean } = {
	["<<"] = true, [">>"] = true, ["&"] = true, ["~"] = true, ["|"] = true,
}

local BITWISE_STOP_SYM: { [string]: boolean } = {
	["<<"] = true, [">>"] = true, ["&"] = true, ["~"] = true, ["|"] = true,
	["=="] = true, ["~="] = true, ["<"] = true, [">"] = true, ["<="] = true, [">="] = true,
	["="] = true, [","] = true, [";"] = true, ["??"] = true,
	["<<="] = true, [">>="] = true, ["+="] = true, ["-="] = true, ["*="] = true,
	["/="] = true, ["//="] = true, ["%="] = true, ["^="] = true, ["..="] = true,
}
local BITWISE_STOP_KW: { [string]: boolean } = {
	["and"] = true, ["or"] = true, ["then"] = true, ["do"] = true, ["end"] = true,
	["else"] = true, ["elseif"] = true, ["until"] = true, ["in"] = true,
	["return"] = true, ["local"] = true, ["if"] = true, ["while"] = true,
	["for"] = true, ["repeat"] = true, ["function"] = true, ["break"] = true,
	["continue"] = true,
}

local function bitwisePrevMakesUnary(prev: Token?): boolean
	if prev == nil then
		return true
	end
	local raw = prev.raw
	if prev.kind == "sym" then

		return not (raw == ")" or raw == "]" or raw == "}" or raw == "...")
	end
	if prev.kind == "kw" then

		return not (raw == "nil" or raw == "true" or raw == "false")
	end

	return false
end

local function bitwiseIsValueEnd(t: Token): boolean
	if t.kind == "id" or t.kind == "num" or t.kind == "str" then
		return true
	end
	if t.kind == "sym" then
		return t.raw == ")" or t.raw == "]" or t.raw == "}" or t.raw == "..."
	end
	if t.kind == "kw" then
		return t.raw == "nil" or t.raw == "true" or t.raw == "false" or t.raw == "end"
	end
	return false
end

local BITWISE_CONTINUE_SYM: { [string]: boolean } = {
	["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["//"] = true,
	["%"] = true, ["^"] = true, [".."] = true,
	["."] = true, [":"] = true, ["["] = true, ["("] = true, ["{"] = true,
}

local function bitwiseCanFollowValue(t: Token): boolean
	if t.kind == "sym" then
		return BITWISE_CONTINUE_SYM[t.raw] == true
	end
	return t.kind == "str"
end

local function bitwiseIsValueStart(t: Token): boolean
	if t.kind == "id" or t.kind == "num" then
		return true
	end
	if t.kind == "kw" then
		return t.raw == "nil" or t.raw == "true" or t.raw == "false"
	end
	return false
end

local function lowerBitwise(source: string): string?
	if #source == 0 or #source > MAX_SOURCE_BYTES then
		return nil
	end
	local first = string.byte(source, 1)
	if first and first < 0x20 then
		return nil
	end

	if not string.find(source, "[~&|<>]") then
		return nil
	end

	local current = source
	local iterations = 0

	local maxIterations = 200000
	while true do
		iterations += 1
		if iterations > maxIterations then
			return nil
		end
		local tokens = Instrument.tokenize(current)
		if #tokens == 0 or #tokens > MAX_TOKENS then
			return nil
		end

		local targetIndex: number? = nil
		local targetRank = -1
		local targetUnary = false
		local prevSignificant: Token? = nil
		for idx, tok in ipairs(tokens) do
			if tok.kind == "comment" then
				continue
			end
			if tok.kind == "sym" and BITWISE_SYM[tok.raw] then
				local unary = tok.raw == "~" and bitwisePrevMakesUnary(prevSignificant)
				local rank = if unary then 6 else BITWISE_RANK[tok.raw]
				if rank > targetRank then
					targetRank = rank
					targetIndex = idx
					targetUnary = unary
				end
			end
			prevSignificant = tok
		end

		if targetIndex == nil then

			return if current == source then nil else current
		end

		local opTok = tokens[targetIndex]

		local function scanForward(fromIdx: number): (number?, number?)
			local depth = 0
			local firstStart: number? = nil
			local lastFinish: number? = nil
			local prevWasValue = false
			for j = fromIdx, #tokens do
				local t = tokens[j]
				if t.kind == "comment" then
					continue
				end
				local raw = t.raw
				if raw == "(" or raw == "[" or raw == "{" then
					depth += 1
				elseif raw == ")" or raw == "]" or raw == "}" then
					if depth == 0 then
						break
					end
					depth -= 1
				elseif depth == 0 then
					if (t.kind == "sym" and BITWISE_STOP_SYM[raw])
						or (t.kind == "kw" and BITWISE_STOP_KW[raw]) then
						break
					end

					if prevWasValue and not bitwiseCanFollowValue(t) then
						break
					end
				end
				if firstStart == nil then
					firstStart = t.start
				end
				lastFinish = t.start + #t.raw - 1
				prevWasValue = bitwiseIsValueEnd(t)
			end
			return firstStart, lastFinish
		end

		local function scanBackward(fromIdx: number): (number?, number?)
			local depth = 0
			local spanStart: number? = nil
			local spanFinish: number? = nil

			local nextAccepted: Token? = nil
			for j = fromIdx, 1, -1 do
				local t = tokens[j]
				if t.kind == "comment" then
					continue
				end
				local raw = t.raw
				if raw == ")" or raw == "]" or raw == "}" then
					depth += 1
				elseif raw == "(" or raw == "[" or raw == "{" then
					if depth == 0 then
						break
					end
					depth -= 1
				elseif depth == 0 then
					if (t.kind == "sym" and BITWISE_STOP_SYM[raw])
						or (t.kind == "kw" and BITWISE_STOP_KW[raw]) then
						break
					end

					if nextAccepted and bitwiseIsValueEnd(t) and bitwiseIsValueStart(nextAccepted) then
						break
					end
				end
				if spanFinish == nil then
					spanFinish = t.start + #t.raw - 1
				end
				spanStart = t.start
				nextAccepted = t
			end
			return spanStart, spanFinish
		end

		local rStart, rFinish = scanForward(targetIndex + 1)
		if rStart == nil or rFinish == nil then
			return nil
		end
		local rightText = string.sub(current, rStart, rFinish)

		local newSource: string
		if targetUnary then

			newSource = string.sub(current, 1, opTok.start - 1)
				.. "bit32.bnot(" .. rightText .. ")"
				.. string.sub(current, rFinish + 1)
		else
			local lStart, lFinish = scanBackward(targetIndex - 1)
			if lStart == nil or lFinish == nil then
				return nil
			end
			local leftText = string.sub(current, lStart, lFinish)
			local fn = BITWISE_BINARY_FN[opTok.raw]

			newSource = string.sub(current, 1, lStart - 1)
				.. "bit32." .. fn .. "(" .. leftText .. ", " .. rightText .. ")"
				.. string.sub(current, rFinish + 1)
		end

		if newSource == current then
			return nil
		end
		current = newSource
	end
end

local GUARD_PRELUDE = table.concat({
	"local _GAnil=function(...)return 0 end;",
	"local _GAnilT=function(...)return 0 end;",
}, "")

local ARITH_SYM: { [string]: boolean } = {
	["+"] = true,
	["-"] = true,
	["*"] = true,
	["/"] = true,
	["%"] = true,
	["^"] = true,
	[".."] = true,
	["#"] = true,
}

local STMT_KW: { [string]: boolean } = {
	["return"] = true,
	["end"] = true,
	["then"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["until"] = true,
	["break"] = true,
	["continue"] = true,
	["in"] = true,
	["function"] = true,
	["local"] = true,
	["repeat"] = true,
	["while"] = true,
	["for"] = true,
	["if"] = true,
	["and"] = true,
	["or"] = true,
	["not"] = true,
}

local function isAtomTok(t: any): boolean
	if type(t) ~= "table" then
		return false
	end
	local k = t.kind
	if k == "kw" then
		return not STMT_KW[t.raw]
	end
	return k == "id" or k == "num" or k == "str"
end

local function scanLeftOperand(toks: { any }, i: number): number?
	local j = i - 1
	if j < 1 then
		return nil
	end
	local t = toks[j]
	if not (isAtomTok(t) or (t.kind == "sym" and (t.raw == ")" or t.raw == "]"))) then
		return nil
	end
	while j >= 1 do
		local tt = toks[j]
		if tt.kind == "sym" and tt.raw == ")" then
			local depth = 0
			while j >= 1 do
				local u = toks[j]
				if u.raw == ")" then
					depth += 1
				elseif u.raw == "(" then
					depth -= 1
					if depth == 0 then
						break
					end
				end
				j -= 1
			end
			if j < 1 then
				return nil
			end
			j -= 1
		elseif tt.kind == "sym" and tt.raw == "]" then
			local depth = 0
			while j >= 1 do
				local u = toks[j]
				if u.raw == "]" then
					depth += 1
				elseif u.raw == "[" then
					depth -= 1
					if depth == 0 then
						break
					end
				end
				j -= 1
			end
			if j < 1 then
				return nil
			end
			j -= 1
			if j >= 1 and toks[j].kind == "id" then
				j -= 1
			end
		elseif tt.kind == "sym" and tt.raw == ":" then
			j -= 1
		elseif tt.kind == "sym" and tt.raw == "." then
			if j + 1 <= #toks and toks[j + 1].kind == "id" then
				j -= 1
			else
				break
			end
		elseif isAtomTok(tt) then
			j -= 1
		else
			break
		end
	end
	local ls = j + 1
	if ls < 1 then
		return nil
	end
	if ls > 1 and toks[ls - 1] ~= nil and toks[ls - 1].kind == "sym" and toks[ls - 1].raw == ":" then
		return nil
	end
	return ls
end

local function scanRightOperand(toks: { any }, i: number): (number?, number?)
	local n = #toks
	local j = i + 1
	if j > n then
		return nil, nil
	end
	local t = toks[j]
	if not (isAtomTok(t) or (t.kind == "sym" and t.raw == "(")) then
		return nil, nil
	end
	while j <= n do
		local tt = toks[j]
		if tt.kind == "sym" and tt.raw == "(" then
			local depth = 0
			while j <= n do
				local u = toks[j]
				if u.raw == "(" then
					depth += 1
				elseif u.raw == ")" then
					depth -= 1
					if depth == 0 then
						break
					end
				end
				j += 1
			end
			if j > n then
				return nil, nil
			end
			j += 1
		elseif tt.kind == "sym" and tt.raw == "[" then
			local depth = 0
			while j <= n do
				local u = toks[j]
				if u.raw == "[" then
					depth += 1
				elseif u.raw == "]" then
					depth -= 1
					if depth == 0 then
						break
					end
				end
				j += 1
			end
			if j > n then
				return nil, nil
			end
			j += 1
		elseif tt.kind == "sym" and (tt.raw == "." or tt.raw == ":") then
			if j + 1 <= n and toks[j + 1].kind == "id" then
				j += 2
			else
				break
			end
		elseif tt.kind == "sym" and tt.raw == "{" then
			local depth = 0
			while j <= n do
				local u = toks[j]
				if u.raw == "{" then
					depth += 1
				elseif u.raw == "}" then
					depth -= 1
					if depth == 0 then
						break
					end
				end
				j += 1
			end
			if j > n then
				return nil, nil
			end
			j += 1
		elseif isAtomTok(tt) then
			j += 1
		else
			break
		end
	end
	return i + 1, j - 1
end

local function guardArith(s: string): (string?, string?, number)
	local ok, toks = pcall(Instrument.tokenize, s)
	if not ok or type(toks) ~= "table" or #toks == 0 then
		return nil, "tokenize failed", 0
	end
	local edits: { { pos: number, text: string, seq: number } } = {}
	local seq = 0
	local nWrapped = 0
	local nCompound = 0
	for i, tok in ipairs(toks) do
		if tok.kind == "sym" and ARITH_SYM[tok.raw] == true then
			local nextTok = toks[i + 1]
			local isCompound = nextTok ~= nil and nextTok.kind == "sym" and nextTok.raw == "="
			local ls = scanLeftOperand(toks, i)
			local rs, re = scanRightOperand(toks, i)
			if isCompound then
				if ls ~= nil and ls == i - 1 and toks[ls].kind == "id" then
					local id = toks[ls].raw
					seq += 1
					edits[#edits + 1] = {
						pos = toks[ls].start,
						text = " if " .. id .. "==nil then " .. id .. "=0 end; ",
						seq = seq,
					}
					if rs ~= nil and re ~= nil and re == rs and toks[rs].kind == "id" then
						local rid = toks[rs].raw
						seq += 1
						edits[#edits + 1] = {
							pos = toks[rs].start,
							text = " if " .. rid .. "==nil then " .. rid .. "=0 end; ",
							seq = seq,
						}
					end
					nCompound += 1
				end
			else
				if rs ~= nil and re ~= nil and re >= rs then
					local closeTxt = if tok.raw == "#" then " or _GAnilT())" else " or _GAnil())"
					seq += 1
					edits[#edits + 1] = { pos = toks[rs].start, text = "(", seq = seq }
					seq += 1
					edits[#edits + 1] = {
						pos = toks[re].start + #toks[re].raw,
						text = closeTxt,
						seq = seq,
					}
					nWrapped += 1
				end
				if ls ~= nil and tok.raw ~= "#" and toks[ls] ~= nil and i > 1 and toks[i - 1] ~= nil then
					local okLs = toks[ls].kind ~= "sym"
					if not okLs and toks[ls].raw == "(" then
						local depth = 0
						local kLs = ls
						local lastLs = nil
						while kLs <= i - 1 do
							local uLs = toks[kLs]
							if uLs.raw == "(" then
								depth += 1
							elseif uLs.raw == ")" then
								depth -= 1
							end
							lastLs = kLs
							if depth == 0 then
								break
							end
							kLs += 1
						end
						okLs = depth == 0 and lastLs == i - 1
					end
					if okLs then
						local lEnd = toks[i - 1].start + #toks[i - 1].raw
						seq += 1
						edits[#edits + 1] = { pos = toks[ls].start, text = "(", seq = seq }
						seq += 1
						edits[#edits + 1] = { pos = lEnd, text = " or _GAnil())", seq = seq }
						nWrapped += 1
					end
				end
			end
		end
	end
	if #edits == 0 then
		return s, nil, 0
	end
	table.sort(edits, function(a, b)
		if a.pos ~= b.pos then
			return a.pos < b.pos
		end
		return a.seq < b.seq
	end)
	local parts: { string } = {}
	local p = 1
	for _, e in ipairs(edits) do
		parts[#parts + 1] = s:sub(p, e.pos - 1)
		parts[#parts + 1] = e.text
		p = e.pos
	end
	parts[#parts + 1] = s:sub(p)
	return table.concat(parts), nil, nWrapped + nCompound
end

Instrument.CHECK_NAME = CHECK_NAME
Instrument.LOCAL_NAME = LOCAL_NAME
Instrument.lowerBitwise = lowerBitwise
Instrument.guardArith = guardArith
Instrument.GUARD_PRELUDE = GUARD_PRELUDE
Instrument.BRANCH_NAME = BRANCH_NAME
Instrument.BRANCH_END_NAME = BRANCH_END_NAME
Instrument.ARG_NAME = ARG_NAME
Instrument.OP_NAME = OP_NAME
Instrument.COMPARISON_OPS = COMPARISON_OPS

return Instrument
