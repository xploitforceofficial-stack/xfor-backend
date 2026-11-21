type Edit = { start: number, finish: number, text: string }

local SrcEdit = {}

local function collectWrapEdits(toks: { any }): { Edit }
	local edits: { Edit } = {}
	local stack: { { kind: string, pos: number } } = {}

	for idx, tok in ipairs(toks) do
		if tok.kind == "kw" then
			if tok.raw == "function" then
				stack[#stack + 1] = { kind = "function", pos = idx }
			elseif tok.raw == "if" or tok.raw == "repeat" or tok.raw == "do" then

				stack[#stack + 1] = { kind = tok.raw, pos = idx }
			elseif tok.raw == "end" or tok.raw == "until" then
				if #stack > 0 then
					local top = stack[#stack]
					table.remove(stack, #stack)

					if top.kind == "function" then
						local isLocalFunc = false
						if top.pos > 1 and toks[top.pos - 1].raw == "local"
							and top.pos + 1 <= #toks and toks[top.pos + 1].kind == "id" then
							isLocalFunc = true
						end

						local isAssignedFunc = false
						local assignNameTok: any = nil
						local assignIsBracket = false
						if top.pos > 2 and toks[top.pos - 1].raw == "=" then
							if toks[top.pos - 2].kind == "id"
								and toks[top.pos - 3] ~= nil
								and toks[top.pos - 3].raw ~= "{" and toks[top.pos - 3].raw ~= "," then
								isAssignedFunc = true
								assignNameTok = toks[top.pos - 2]
							elseif toks[top.pos - 2].raw == "]" then

								local depth2 = 0
								local isTableKey = false
								for k = top.pos - 2, 1, -1 do
									if toks[k].raw == "]" then depth2 += 1
									elseif toks[k].raw == "[" then
										depth2 -= 1
										if depth2 == 0 then
											local before: any = toks[k - 1]
											if before and (before.raw == "{" or before.raw == ",") then
												isTableKey = true
											end
											break
										end
									end
								end
								if not isTableKey then
									isAssignedFunc = true
									assignIsBracket = true
								end
							end
						end

						if isLocalFunc then
							local nameTok: any = nil
							for k = top.pos + 1, #toks do
								if toks[k].kind == "id" then
									nameTok = toks[k]
									break
								end
								if toks[k].raw == "(" then
									break
								end
							end
							if nameTok then
								local endPos = tok.start + #tok.raw

								edits[#edits + 1] = {
									start = endPos,
									finish = endPos - 1,
									text = "; " .. nameTok.raw .. " = __wrapFunc(" .. nameTok.raw .. ")",
								}
							end
						elseif isAssignedFunc then
							local endPos = tok.start + #tok.raw
							if assignIsBracket then

								local eqIdx = top.pos - 1

								local lhsStartIdx = eqIdx - 1
								local depth = 0
								while lhsStartIdx >= 1 do
									local t: any = toks[lhsStartIdx]
									if t.raw == "]" then depth += 1
									elseif t.raw == "[" then
										if depth == 0 then

										else depth -= 1 end
									elseif depth == 0 and (t.raw == "," or t.raw == ";" or t.raw == "local" or t.raw == "return" or t.raw == "and" or t.raw == "or" or t.raw == "if" or t.raw == "then" or t.raw == "{" or t.raw == "}" or t.raw == "(" or t.raw == ")") then
										break
									end
									lhsStartIdx -= 1
								end
								lhsStartIdx += 1
								local lhsStart = toks[lhsStartIdx].start
								local lhsEnd = toks[eqIdx - 1].start + #toks[eqIdx - 1].raw - 1
								local lhsText = string.sub(toks.src, lhsStart, lhsEnd)
								edits[#edits + 1] = {
									start = endPos,
									finish = endPos - 1,
									text = "; " .. lhsText .. " = __wrapFunc(" .. lhsText .. ")",
								}
							else

								edits[#edits + 1] = {
									start = endPos,
									finish = endPos - 1,
									text = "; " .. assignNameTok.raw .. " = __wrapFunc(" .. assignNameTok.raw .. ")",
								}
							end
							isAssignedFunc = false
						else
							local funcStart = toks[top.pos].start
							local funcEnd = tok.start + #tok.raw - 1
							edits[#edits + 1] = {
								start = funcStart,
								finish = funcEnd,
								text = "__wrapFunc(" .. string.sub(toks.src, funcStart, funcEnd) .. ")",
							}
						end
					end
				end
			end
		end
	end

	return edits
end

function SrcEdit.apply(src: string, edits: { Edit }): string
	if #edits == 0 then
		return src
	end
	local sorted: { Edit } = table.clone(edits)
	table.sort(sorted, function(a, b)
		if a.start == b.start then
			return a.finish < b.finish
		end
		return a.start < b.start
	end)

	local pieces: { string } = {}
	local cursor = 1
	for _, e in ipairs(sorted) do

		if e.start < cursor then
			continue
		end
		if e.start > cursor then
			pieces[#pieces + 1] = string.sub(src, cursor, e.start - 1)
		end
		pieces[#pieces + 1] = e.text
		cursor = e.finish + 1
	end
	if cursor <= #src then
		pieces[#pieces + 1] = string.sub(src, cursor)
	end
	return table.concat(pieces)
end

local SAFE_NAME = "__FUHD_SAFE__"
local SAFE_INDEX_NAME = "__FUHD_SAFE_INDEX__"
local SAFE_SET_NAME = "__FUHD_SAFE_SET__"

	local SAFE_KEYS: { [string]: boolean } = {
		FindFirstChild = true, FindFirstChildOfClass = true, FindFirstChildWhichIsA = true,
		WaitForChild = true, GetService = true, GetChildren = true, GetDescendants = true,
		FindFirstAncestor = true, FindFirstAncestorOfClass = true, FindFirstAncestorWhichIsA = true,
		ForceCheckbox = true,

		Position = true, SetControlPoints = true, GetControlPoints = true,
		GetPointPosition = true, HumanoidRootPart = true, CurrentCamera = true,
	}

local function isMethodColon(toks: { any }, idx: number): boolean
	local nxt: any = toks[idx + 1]
	if nxt == nil or nxt.kind ~= "id" then return false end
	local after: any = toks[idx + 2]
	if after == nil then return false end
	return after.raw == "(" or after.raw == "{" or after.kind == "str"
end

local function openerOf(toks: { any }, closeIdx: number): number?
	local depth = 0
	local i = closeIdx
	while i >= 1 do
		local raw = toks[i].raw
		if raw == ")" or raw == "]" or raw == "}" then
			depth += 1
		elseif raw == "(" or raw == "[" or raw == "{" then
			depth -= 1
			if depth == 0 then
				return i
			end
		end
		i -= 1
	end
	return nil
end

local function baseStartOf(toks: { any }, opIdx: number): number?
	local i = opIdx - 1
	if i < 1 then
		return nil
	end
	local start = i
	while i >= 1 do
		local tok: any = toks[i]
		local raw = tok.raw
		if raw == ")" or raw == "]" or raw == "}" then
			local open = openerOf(toks, i)
			if open == nil then
				return start
			end
			if toks[open].raw == "{" then

				return open
			end
			start = open
			if open - 1 < 1 then
				return open
			end
			local before: any = toks[open - 1]

			if before.raw == ")" then
				local pOpen = openerOf(toks, open - 1)
				if pOpen ~= nil and pOpen > 1 and toks[pOpen - 1].raw == "function" then
					return open
				end
			end
			if before.kind == "id" or before.raw == ")" or before.raw == "]" or before.raw == "}" then
				i = open - 1
				start = i
			elseif before.raw == "." or before.raw == ":" then
				i = open - 2
				start = i
			else

				return open
			end
		elseif tok.kind == "id" then

			local j = i - 1
			while j >= 1 do
				local sep: any = toks[j]
				if (sep.raw == "." or sep.raw == ":") and j >= 2 then
					local before: any = toks[j - 1]
					if before.kind == "id" then
						j -= 2
					elseif before.raw == ")" then
						local open = openerOf(toks, j - 1)
						local fn = if open and open > 1 then toks[open - 1] else nil
						if fn and fn.kind == "id" and (fn.raw == SAFE_INDEX_NAME or fn.raw == SAFE_NAME) then
							if open - 2 >= 1 and (toks[open - 2].raw == "." or toks[open - 2].raw == ":") then
								j = open - 2
							else
								return open - 1
							end
						else
							break
						end
					else
						break
					end
				elseif sep.raw == "]" then
					local open = openerOf(toks, j)
					if open == nil then
						break
					end
					j = open - 1
				else
					break
				end
			end
			return j + 1
		else
			return start
		end
	end
	return start
end

local function baseStartOfIndex(toks: { any }, bracketIdx: number): number?
	return baseStartOf(toks, bracketIdx)
end

local function baseStartOfColon(toks: { any }, colonIdx: number): number?
	return baseStartOf(toks, colonIdx)
end

local function findMatchingBracket(toks: { any }, openIdx: number): number?
	local depth = 0
	for i = openIdx, #toks do
		if toks[i].raw == "[" then depth += 1
		elseif toks[i].raw == "]" then
			depth -= 1
			if depth == 0 then return i end
		end
	end
	return nil
end

local function collectSafeIndexEdits(toks: { any }, wrapAllProps: boolean?): { Edit }
	local edits: { Edit } = {}
	for idx, tok in ipairs(toks) do
		if tok.raw == "[" then
			local prev: any = toks[idx - 1]
			if prev == nil then continue end
			if prev.raw == "{" or prev.raw == "," or prev.raw == "=" then
				continue
			end
			local closeIdx = findMatchingBracket(toks, idx)
			if closeIdx == nil then continue end

			local nxt: any = toks[closeIdx + 1]
			if nxt and nxt.raw == "=" then

				local sIdxB = baseStartOfIndex(toks, idx)
				if sIdxB ~= nil and sIdxB < idx then

					do
						local depthBack = 0
						for k = sIdxB - 1, 1, -1 do
							local rawB = toks[k].raw
							if rawB == ")" or rawB == "]" or rawB == "}" then
								depthBack += 1
							elseif rawB == "(" or rawB == "[" or rawB == "{" then
								depthBack -= 1
							elseif depthBack == 0 then
								if rawB == "," then
									sIdxB = nil
									break
								elseif rawB == ";" or rawB == "do" or rawB == "then"
									or rawB == "end" or rawB == "until" or rawB == "local"
									or rawB == "return" or rawB == "function" or rawB == "else"
									or rawB == "elseif" or rawB == "if" or rawB == "while"
									or rawB == "for" or rawB == "repeat" or rawB == "=" then
									break
								end
							end
						end
					end
				end
				if sIdxB ~= nil and sIdxB < idx then
					local bStart = toks[sIdxB].start
					local bEnd = prev.start + #prev.raw - 1
					local bText = string.sub(toks.src, bStart, bEnd)
					local kStart = toks[idx + 1] and toks[idx + 1].start or (toks[idx].start + 1)
					local kEnd = (toks[closeIdx - 1] and toks[closeIdx - 1].start + #toks[closeIdx - 1].raw - 1) or (toks[closeIdx].start - 1)
					local kText = ""
					if kStart <= kEnd then
						kText = string.sub(toks.src, kStart, kEnd)
					end
					local rhsStart = nxt.start + #nxt.raw
					local depth = 0
					local blockDepth = 0
					local endIdx = #toks
					local firstRhs = closeIdx + 2
					for k = firstRhs, #toks do
						local tok = toks[k]
						local raw = tok.raw
						if raw == "(" or raw == "[" or raw == "{" then
							depth += 1
						elseif raw == ")" or raw == "]" or raw == "}" then
							depth -= 1
						elseif depth == 0 and raw == "function" then
							blockDepth += 1
						elseif depth == 0 and blockDepth > 0 and (raw == "if" or raw == "do" or raw == "repeat") then
							blockDepth += 1
						elseif depth == 0 and blockDepth > 0 and (raw == "end" or raw == "until") then
							blockDepth -= 1
						elseif depth == 0 and blockDepth == 0 and raw == ";" then
							endIdx = k - 1
							break
						elseif depth == 0 and blockDepth == 0 and k > firstRhs and (raw == "then" or raw == "else"
							or raw == "elseif" or raw == "end" or raw == "until" or raw == "local"
							or raw == "return" or raw == "do" or raw == "while"
							or raw == "for" or raw == "repeat") then
							endIdx = k - 1
							break
						elseif depth == 0 and blockDepth == 0 and k > firstRhs and tok.kind == "id" then
							local prevT = toks[k - 1]
							local pr = prevT.raw
							local valueEnded = prevT.kind == "id" or prevT.kind == "num"
								or prevT.kind == "str" or pr == ")" or pr == "]" or pr == "}"
								or pr == "true" or pr == "false" or pr == "nil" or pr == "end"
							if valueEnded then
								endIdx = k - 1
								break
							end
						end
					end
					local rhsEndTok = toks[math.min(endIdx, #toks)]
					local rhsEnd = rhsEndTok.start + #rhsEndTok.raw - 1
					local rhsText = ""
					if rhsStart <= rhsEnd then
						rhsText = string.sub(toks.src, rhsStart, rhsEnd)
					end
					if #bText > 0 and #bText <= 800 and #kText > 0 and #kText <= 800 and #rhsText > 0 and #rhsText <= 8000 then
						edits[#edits + 1] = {
							start = bStart,
							finish = rhsEnd,
							text = " " .. SAFE_SET_NAME .. "(" .. bText .. ", (" .. kText .. "), (" .. rhsText .. "))",
						}
						continue
					end
				end
				continue
			end

			do
				local raw = nxt and nxt.raw or nil
				local isAssign = raw == "+=" or raw == "-=" or raw == "*=" or raw == "/="
					or raw == "%=" or raw == "^=" or raw == "..="
				if not isAssign and raw ~= nil then
					local splitsInto = raw == "+" or raw == "-" or raw == "*" or raw == "/"
						or raw == "%" or raw == "^" or raw == ".."
					if splitsInto then
						local after = toks[closeIdx + 2]

						if after and after.raw == "=" then
							isAssign = true
						end
					end
				end
				if isAssign then continue end
			end

			if nxt and nxt.raw == "," then
				local isLHS = false

				for k = closeIdx + 1, math.min(closeIdx + 40, #toks) do
					local raw = toks[k].raw
					if raw == "=" then isLHS = true; break end
					if raw == ";" or raw == "do" or raw == "then" or raw == "end"
						or raw == "until" or raw == "local" or raw == "return"
						or raw == "function" or raw == "while" or raw == "repeat"
						or raw == "for" or raw == "if" then
						break
					end
				end
				if isLHS then continue end
			end
			do

				local after = toks[closeIdx + 1]
				if after and after.kind == "id" then
					continue
				end
			end
			local sIdx = baseStartOfIndex(toks, idx)
			if sIdx == nil or sIdx >= idx then continue end
			local baseStart = toks[sIdx].start
			local baseEnd = prev.start + #prev.raw - 1
			local baseText = string.sub(toks.src, baseStart, baseEnd)
			local innerStart = toks[idx + 1] and toks[idx + 1].start or (toks[idx].start + 1)
			local innerEnd = toks[closeIdx - 1] and (toks[closeIdx - 1].start + #toks[closeIdx - 1].raw - 1) or (toks[closeIdx].start - 1)
			local innerText = ""
			if innerStart <= innerEnd then
				innerText = string.sub(toks.src, innerStart, innerEnd)
			end
			if #baseText == 0 or #baseText > 800 or #innerText == 0 or #innerText > 800 then continue end

			local innerTrim = string.gsub(innerText, "^%s+", "")
			innerTrim = string.gsub(innerTrim, "%s+$", "")

			if #innerTrim == 0 then continue end
			local wholeStart = baseStart
			local wholeEnd = toks[closeIdx].start + #toks[closeIdx].raw - 1
			edits[#edits + 1] = { start = wholeStart, finish = wholeEnd, text = " " .. SAFE_INDEX_NAME .. "(" .. baseText .. ", " .. innerText .. ")" }
		elseif tok.raw == "." then
			local nxt: any = toks[idx + 1]
			if nxt and nxt.kind == "id" and (SAFE_KEYS[nxt.raw] or wrapAllProps == true) then
				local prev: any = toks[idx - 1]

				local prevOk = prev ~= nil and (
					prev.kind == "id" or prev.raw == ")" or prev.raw == "]"
					or (prev.kind == "kw" and (prev.raw == "nil" or prev.raw == "true" or prev.raw == "false"))
				)
				if not prevOk then continue end

				local afterKey: any = toks[idx + 2]
				if afterKey and afterKey.raw == "=" and wrapAllProps == true then
					local sIdxA = baseStartOfIndex(toks, idx)
					if sIdxA ~= nil and sIdxA < idx then
						local bStart = toks[sIdxA].start
						local bEnd = prev.start + #prev.raw - 1
						local bText = string.sub(toks.src, bStart, bEnd)
						local rhsStart = afterKey.start + #afterKey.raw
						local rhsEndIdx = idx + 2

						local depth = 0
						local blockDepth = 0
						local endIdx = #toks
						local firstRhs = idx + 3
						for k = firstRhs, #toks do
							local tok = toks[k]
							local raw = tok.raw
							if raw == "(" or raw == "[" or raw == "{" then
								depth += 1
							elseif raw == ")" or raw == "]" or raw == "}" then
								depth -= 1
							elseif depth == 0 and raw == "function" then
								blockDepth += 1
							elseif depth == 0 and blockDepth > 0 and (raw == "if" or raw == "do" or raw == "repeat") then
								blockDepth += 1
							elseif depth == 0 and blockDepth > 0 and (raw == "end" or raw == "until") then
								blockDepth -= 1
							elseif depth == 0 and blockDepth == 0 and raw == ";" then
								endIdx = k - 1
								break
							elseif depth == 0 and blockDepth == 0 and k > firstRhs and (raw == "then" or raw == "else"
								or raw == "elseif" or raw == "end" or raw == "until" or raw == "local"
								or raw == "return" or raw == "do" or raw == "while"
								or raw == "for" or raw == "repeat") then
								endIdx = k - 1
								break
							elseif depth == 0 and blockDepth == 0 and k > firstRhs and tok.kind == "id" then

								local prevT = toks[k - 1]
								local pr = prevT.raw
								local valueEnded = prevT.kind == "id" or prevT.kind == "num"
									or prevT.kind == "str" or pr == ")" or pr == "]" or pr == "}"
									or pr == "true" or pr == "false" or pr == "nil" or pr == "end"
								if valueEnded then
									endIdx = k - 1
									break
								end
							end
						end
						local rhsEndTok = toks[math.min(endIdx, #toks)]
						local rhsEnd = rhsEndTok.start + #rhsEndTok.raw - 1
						local rhsText = ""
						if rhsStart <= rhsEnd then
							rhsText = string.sub(toks.src, rhsStart, rhsEnd)
						end
						if #bText > 0 and #bText <= 800 and #rhsText > 0 and #rhsText <= 8000 then
							edits[#edits + 1] = {
								start = bStart,
								finish = rhsEnd,
								text = " " .. SAFE_SET_NAME .. "(" .. bText .. ", \"" .. nxt.raw .. "\", (" .. rhsText .. "))",
							}
						end
					end
					continue
				end
				if afterKey and afterKey.raw == "=" then continue end

				local sIdx = baseStartOfIndex(toks, idx)
				if sIdx == nil or sIdx >= idx then
					if prev.kind == "kw" then
						edits[#edits + 1] = {
							start = prev.start,
							finish = nxt.start + #nxt.raw - 1,
							text = " " .. SAFE_INDEX_NAME .. "(" .. prev.raw .. ", \"" .. nxt.raw .. "\")",
						}
					end
					continue
				end
				local baseStart = toks[sIdx].start
				local baseEnd = prev.start + #prev.raw - 1
				local baseText = string.sub(toks.src, baseStart, baseEnd)
				if #baseText == 0 or #baseText > 800 then continue end
				edits[#edits + 1] = {
					start = baseStart,
					finish = nxt.start + #nxt.raw - 1,
					text = " " .. SAFE_INDEX_NAME .. "(" .. baseText .. ", \"" .. nxt.raw .. "\")",
				}
			end
		elseif tok.raw == ":" and isMethodColon(toks, idx) then
			local nxt: any = toks[idx + 1]
			if nxt == nil or nxt.kind ~= "id" then continue end
			if not SAFE_KEYS[nxt.raw] and wrapAllProps ~= true then continue end
			local sIdx = baseStartOfColon(toks, idx)
			if sIdx == nil or sIdx >= idx then continue end
			local prev: any = toks[idx - 1]
			local baseStart = toks[sIdx].start
			local baseEnd = prev.start + #prev.raw - 1
			local baseText = string.sub(toks.src, baseStart, baseEnd)
			if #baseText == 0 or #baseText > 800 then continue end
			if string.sub(baseText, 1, #SAFE_NAME + 1) == SAFE_NAME .. "(" then
				continue
			end
			if string.sub(baseText, 1, #SAFE_INDEX_NAME + 1) == SAFE_INDEX_NAME .. "(" then
				continue
			end

			edits[#edits + 1] = { start = baseStart, finish = baseEnd, text = SAFE_NAME .. "(" .. baseText .. ")" }
		end
	end
	return edits
end

function SrcEdit.wrapSafeIndexing(src: string, tokenize: (string) -> any, wrapAllProps: boolean?): (string?, string?)

	local current = src
	local totalEdits = 0
	for _pass = 1, 8 do
		local okTok, toks = pcall(tokenize, current)
		if not okTok or type(toks) ~= "table" or #toks == 0 then
			if totalEdits == 0 then
				return nil, "token fail"
			end
			break
		end
		toks.src = current
		local edits = collectSafeIndexEdits(toks, wrapAllProps)
		if #edits == 0 then
			break
		end
		local nxt = SrcEdit.apply(current, edits)
		totalEdits += #edits
		if nxt == current then
			break
		end
		current = nxt
	end
	if totalEdits == 0 then
		return nil, "no edits"
	end
	return current, nil
end

function SrcEdit.wrapFunctions(src: string, tokenize: (string) -> any): (string?, string?)
	local okTok, toks = pcall(tokenize, src)
	if not okTok or type(toks) ~= "table" or #toks == 0 then
		return nil, "token fail"
	end
	toks.src = src

	local edits = collectWrapEdits(toks)
	if #edits == 0 then
		return nil, "no edits"
	end
	return SrcEdit.apply(src, edits), nil
end

return SrcEdit
