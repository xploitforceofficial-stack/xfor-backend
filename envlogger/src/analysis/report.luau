local Serializer = require("../core/serializer")
local AntiEnvDetect = require("../env/antienv_detect")

local MAX_HEX_BYTES = 2097152

local Report = {}

local HEADER = "-- fuhed at OmniDBF .gg/odbf"

local RUNTIME_WARNING = "-- damn, this script was generated on runtime and its output will be trash"

Report.HEADER = HEADER
Report.RUNTIME_WARNING = RUNTIME_WARNING

export type Options = {

	includeLog: boolean?,

	includeArtifacts: boolean?,

	maxStatements: number?,

	includeOps: boolean?,

	includeStages: boolean?,

	includeBranches: boolean?,

	exploreBranches: boolean?,

	notes: boolean?,
}

local function extendsPath(inner: string, outer: string): boolean
	if #outer <= #inner then
		return false
	end
	if string.sub(outer, 1, #inner) ~= inner then
		return false
	end
	local suffix = string.sub(outer, #inner + 1)

	return string.match(suffix, "^[%.%[:%(]") ~= nil
end

local function branchKey(text: string): string
	text = string.gsub(text, " %-%-didnt ran$", "")
	text = string.gsub(text, " %-%-did ran$", "")
	return text
end

type Statement = {
	text: string,
	kind: string,
	nest: number,

	envRead: boolean?,

	opens: boolean?,

	elseIf: boolean?,

	branchId: number?,

	repeats: number?,

	renderId: number?,

	valueId: number?,

	writeKey: string?,
	readKey: string?,

	writeValue: string?,

	constructorClass: string?,

	connectBaseId: number?,
	connectEvent: string?,
}

local function reconstruct(trace: any, maxStatements: number, includeBranches: boolean?): ({ Statement }, boolean, { [string]: boolean }, { [string]: boolean })
	local statements: { Statement } = {}
	local truncated = false

	local records = trace.records
	local total = #records

	local envReceiver: string?
	for i = 1, total do
		local r = records[i]
		if r.kind == "call" and r.detail and type(r.detail.callee) == "string" then
			local callee = r.detail.callee
			if callee == "getfenv" or callee == "getgenv" or callee == "getrenv" then
				envReceiver = callee
				break
			end
		end
	end

	local function repeatSuffix(record: any): string
		local detail = record.detail
		if detail ~= nil then
			local repeats = tonumber(detail.repeats) or 0
			if repeats >= 2 then
				return string.format(" --[[ x%d ]]", repeats)
			end
		end
		return ""
	end

	local index = 1
	while index <= total do
		local record = records[index]
		local kind = record.kind

		if kind == "index" then

			if record.detail and record.detail.undefinedGlobal then
				index += 1
				continue
			end

			local deepest = record
			local scan = index + 1
			while scan <= total do
				local nextRecord = records[scan]
				if nextRecord.kind == "index" and extendsPath(deepest.expression, nextRecord.expression) then
					deepest = nextRecord
					scan += 1
				else
					break
				end
			end

			local following = records[scan]
			local consumed = false
			if following then
				if following.kind == "call" or following.kind == "namecall" or following.kind == "newindex" then
					if string.find(following.expression, deepest.expression, 1, true) == 1 then
						consumed = true
					else

						local lastDot = string.find(deepest.expression, "%.[%w_]+$")
						if lastDot then
							local receiver = string.sub(deepest.expression, 1, lastDot - 1)
							local member = string.sub(deepest.expression, lastDot + 1)
							local methodForm = receiver .. ":" .. member
							consumed = string.find(following.expression, methodForm, 1, true) == 1
						end

						if not consumed and following.kind == "newindex"
							and #following.expression > #deepest.expression
							and string.sub(following.expression, -#deepest.expression) == deepest.expression
						then
							consumed = true
						end
					end
				elseif following.kind == "branch" or following.kind == "op" then

					local branchRec = following
					if branchRec.kind == "op" then
						local afterOp = records[scan + 1]
						branchRec = if afterOp ~= nil and afterOp.kind == "branch" then afterOp else nil
					end
					if branchRec ~= nil then

						local fExpr = string.gsub(branchRec.expression, "'", '"')
						local dExpr = string.gsub(deepest.expression, "'", '"')
						consumed = string.find(fExpr, dExpr, 1, true) ~= nil
					end
				end
			end

			if not consumed then

				local readExpr = deepest.expression
				local envRead = deepest.detail ~= nil and deepest.detail.global == true
					and deepest.detail.base == "<env>"
				if envRead then

					local accessor = deepest.detail.envVia or envReceiver or "getfenv"
					if string.match(readExpr, "^[%w_]+$") then
						readExpr = if accessor == "_G"
							then "_G." .. readExpr
							else accessor .. "()." .. readExpr
					end
				end
				local repeats = tonumber(deepest.detail and deepest.detail.repeats) or 1
				statements[#statements + 1] = {

					text = "local _ = " .. readExpr .. (if envRead then "" else repeatSuffix(deepest)),
					kind = "index",
					nest = deepest.nest,
					envRead = envRead,
					repeats = repeats,
					renderId = deepest.detail and deepest.detail.renderId,
					readKey = deepest.detail and type(deepest.detail.key) == "string" and deepest.detail.key or nil,
				}
			end
			index = scan
		elseif kind == "call" or kind == "namecall" then

			local nextRecord = records[index + 1]
			local callConsumed = nextRecord ~= nil
				and nextRecord.kind == "index"
				and extendsPath(record.expression, nextRecord.expression)
			if not callConsumed then

				callConsumed = nextRecord ~= nil
					and nextRecord.kind == "newindex"
					and #nextRecord.expression > #record.expression
					and string.sub(nextRecord.expression, -#record.expression) == record.expression
			end

			local skipNewindex = false
			if not callConsumed and nextRecord ~= nil and nextRecord.kind == "newindex" then
				local detail = record.detail
				local callee = detail and detail.callee
				local method = detail and detail.method
				local isChildFinder = type(method) == "string" and (
					method == "WaitForChild"
					or method == "FindFirstChild"
					or method == "FindFirstChildOfClass"
					or method == "FindFirstChildWhichIsA"
				)
				if type(callee) == "string" and isChildFinder then
					local valueExpr = string.match(nextRecord.expression, "^[^=]+=%s*(.-)%s*$")
					local anchored = valueExpr ~= nil
						and (string.sub(valueExpr, 1, #callee + 1) == callee .. ":"
							or string.sub(valueExpr, 1, #callee + 1) == callee .. ".")

					local argName = (detail.arguments and string.match(tostring(detail.arguments), "^%s*\"([^\"]*)\""))
					local argMatches = argName == nil
						or (valueExpr ~= nil and string.find(valueExpr, argName, 1, true) ~= nil)
					if anchored and argMatches then
						local target = string.match(nextRecord.expression, "^%s*([^=]+)=")
						target = string.match(target, "^%s*(.-)%s*$")
						statements[#statements + 1] = {
							text = string.format("%s = %s", target, record.expression),
							kind = "newindex",
							nest = nextRecord.nest,
						}
						callConsumed = true
						skipNewindex = true
					end
				end
			end

			if not callConsumed and nextRecord ~= nil and (nextRecord.kind == "branch" or nextRecord.kind == "op") then
				local branchRec = nextRecord
				if branchRec.kind == "op" then
					local afterOp = records[index + 2]
					branchRec = if afterOp ~= nil and afterOp.kind == "branch" then afterOp else nil
				end
				if branchRec ~= nil then
					local fExpr = string.gsub(branchRec.expression, "'", '"')
					local cExpr = string.gsub(record.expression, "'", '"')
					callConsumed = string.find(fExpr, cExpr, 1, true) ~= nil
				end
			end
			if not callConsumed then

				statements[#statements + 1] = {
					text = record.expression .. repeatSuffix(record),
					kind = kind,
					nest = record.nest,
				}

				local d = record.detail
				if d and d.callback == true then
					statements[#statements].connectBaseId = d.baseId
					statements[#statements].connectEvent = if type(d.event) == "string" then d.event else nil
				end
			end
			index += if skipNewindex then 2 else 1
		elseif kind == "newindex" then
			local text = record.expression
			local detail = record.detail
			if detail and detail.global == true and type(detail.key) == "string" then

				local accessor = detail.envVia or envReceiver
				if accessor then
					local eq = string.find(record.expression, " = ", 1, true)
					if eq then
						local valueText = string.sub(record.expression, eq + 3)
						local prefix = if accessor == "_G" then "_G." else accessor .. "()."
						text = prefix .. detail.key .. " = " .. valueText
					end
				end
			end
			statements[#statements + 1] = { text = text .. repeatSuffix(record), kind = kind, nest = record.nest }

			local stmt = statements[#statements]
			if detail then
				stmt.renderId = detail.renderId
				stmt.valueId = detail.valueId
				if type(detail.key) == "string" then
					stmt.writeKey = detail.key
				end
				local eqPos = string.find(record.expression, " = ", 1, true)
				if eqPos then
					stmt.writeValue = string.sub(record.expression, eqPos + 3)
				end
			end
			local prev = records[index - 1]
			if prev ~= nil and prev.kind == "call" and prev.detail and prev.detail.constructor
				and type(prev.expression) == "string"
				and string.find(record.expression, prev.expression, 1, true) ~= nil
			then
				stmt.constructorClass = prev.detail.className or "Instance"
				stmt.renderId = prev.detail.renderId
			end
			index += 1
		elseif kind == "output" then
			local channel = (record.detail and record.detail.channel) or "print"

			local args = record.detail and record.detail.args
			local text
			if args and #args > 0 then
				local rendered = table.create(#args)
				for i, arg in ipairs(args) do
					rendered[i] = if arg.isString then Serializer.stringLiteral(arg.text) else arg.text
				end
				text = string.format("%s(%s)", channel, table.concat(rendered, ", "))
			elseif record.expression ~= "" then
				text = string.format("%s(%s)", channel, Serializer.stringLiteral(record.expression))
			else

				text = channel .. "()"
			end
			statements[#statements + 1] = {
				text = text,
				kind = "output",
				nest = record.nest,
			}
			index += 1
		elseif kind == "http" then

			local previous = records[index - 1]
			if previous and (previous.kind == "call" or previous.kind == "namecall") then
				index += 1
				continue
			end
			local method = (record.detail and record.detail.method) or "GET"
			local text
			if method == "REQUEST" then
				text = string.format("request({ Url = %s })", Serializer.stringLiteral(record.expression))
			elseif method == "POST" then
				text = string.format("game:HttpService:PostAsync(%s)", Serializer.stringLiteral(record.expression))
			elseif method == "WEBSOCKET" then
				text = string.format("WebSocket.connect(%s)", Serializer.stringLiteral(record.expression))
			else
				text = string.format("game:HttpGet(%s)", Serializer.stringLiteral(record.expression))
			end
			statements[#statements + 1] = { text = text, kind = "http", nest = record.nest }
			index += 1
		elseif kind == "branch" then

			if includeBranches ~= false then

				local comment = if record.detail and record.detail.outcome then "--did ran" else "--didnt ran"
				local kind = record.detail and record.detail.kind
				local kw = if kind == "elseif" then "elseif" elseif kind == "else" then "else" else "if"

				local cond = string.gsub(record.expression, "[\r\n\t]+", " ")
				if #cond > 200 then
					cond = string.sub(cond, 1, 200) .. "..."
				end

				local text = if kw == "else"
					then string.format("%s %s", kw, comment)
					else string.format("%s %s then %s", kw, cond, comment)
				statements[#statements + 1] = {
					text = text,
					kind = "branch",
					nest = record.nest,
					opens = record.detail and record.detail.opens ~= false,
					elseIf = record.detail and (kind == "elseif" or kind == "else"),
					branchId = record.detail and record.detail.srcId,
				}
			end
			index += 1
		elseif kind == "branch_end" then

			if includeBranches ~= false then
				statements[#statements + 1] = { text = "end", kind = "branch_end", nest = record.nest }
			end
			index += 1
		elseif kind == "note" then

			local expr = string.gsub(tostring(record.expression or ""), "[\r\n]+", " ")
			if #expr > 200 then
				expr = string.sub(expr, 1, 197) .. "..."
			end
			statements[#statements + 1] = {
				text = "-- " .. expr,
				kind = "note",
				nest = record.nest,
			}
			index += 1
		elseif kind == "op" then

			if includeBranches ~= false and record.detail and record.detail.concrete == false then
				local expr = string.gsub(record.expression, "[\r\n\t]+", " ")
				expr = string.gsub(expr, "%]%]", "] ]")
				if #expr > 160 then
					expr = string.sub(expr, 1, 160) .. "..."
				end
				statements[#statements + 1] = {
					text = string.format(
						"--[[ guessed: %s -> %s (an operand was unknown) ]]",
						expr,
						tostring(record.detail.outcome)
					),
					kind = "note",
					nest = record.nest,
				}
			end
			index += 1
		elseif kind == "loadstring" then

			index += 1
		else
			index += 1
		end
	end

	local MERGE_CAP = 150000

	if #statements <= MERGE_CAP then
	do
		local hasReads = false
		for j = 1, #statements do
			if statements[j].envRead then
				hasReads = true
				break
			end
		end
		if hasReads then
			local counts: { [string]: { [string]: number } } = {}
			local order: { string } = {}
			local summaryNest = 0
			local sawFirstRead = false
			local function bump(accessor: string, name: string, weight: number)
				if counts[accessor] == nil then
					counts[accessor] = {}
					order[#order + 1] = accessor
				end
				counts[accessor][name] = (counts[accessor][name] or 0) + weight
			end
			for _, stmt in ipairs(statements) do
				if stmt.envRead then
					if not sawFirstRead then
						sawFirstRead = true
						summaryNest = stmt.nest
					end
					local accessor = string.match(stmt.text, "^local _ = ([%w_]+)")
					local name = string.match(stmt.text, "%.([%w_]+)$")
					if accessor and name then

						bump(accessor, name, tonumber(stmt.repeats) or 1)
					end
				end
			end
			local summaries: { Statement } = {}
			for _, accessor in ipairs(order) do
				local names = counts[accessor]
				local ordered: { string } = {}
				for name in pairs(names) do
					ordered[#ordered + 1] = name
				end
				table.sort(ordered)
				local parts: { string } = {}
				for idx, name in ipairs(ordered) do
					if idx > 40 then
						parts[#parts + 1] = string.format("... %d more", #ordered - idx + 1)
						break
					end
					parts[#parts + 1] = if names[name] > 1
						then string.format("%s (x%d)", name, names[name])
						else name
				end
				local receiver = if accessor == "_G" then "_G" else accessor .. "()"
				summaries[#summaries + 1] = {
					text = string.format("--[[ %s reads: %s ]]", receiver, table.concat(parts, ", ")),
					kind = "index",
					nest = summaryNest,
				}
			end
			local merged: { Statement } = {}
			local inserted = false
			for _, stmt in ipairs(statements) do
				if stmt.envRead then
					if not inserted then
						inserted = true
						for _, s in ipairs(summaries) do
							merged[#merged + 1] = s
						end
					end
				else
					merged[#merged + 1] = stmt
				end
			end
			statements = merged
		end
	end

	do
		local merged: { Statement } = {}
		local j = 1
		while j <= #statements do
			if statements[j].kind == "index" and not statements[j].envRead
				and string.match(statements[j].text, "^local _ = ") ~= nil
			then
				local suffix = string.match(statements[j].text, "%.([%w_]+)$")
				if suffix then
					local run = 1
					while j + run <= #statements
						and statements[j + run].kind == "index"
						and not statements[j + run].envRead
						and string.match(statements[j + run].text, "^local _ = ") ~= nil
						and string.match(statements[j + run].text, "%.([%w_]+)$") == suffix
					do
						run += 1
					end
					if run >= 3 then
						merged[#merged + 1] = {
							text = string.format("--[[ .%s read across %d receivers ]]", suffix, run),
							kind = "note",
							nest = statements[j].nest,
						}
						j += run
						continue
					end
				end
			end
			merged[#merged + 1] = statements[j]
			j += 1
		end
		statements = merged
	end

	do
		local merged: { Statement } = {}
		local j = 1
		while j <= #statements do
			local receiver = string.match(statements[j].text, "^([%w_]+) = \"")
			if statements[j].kind == "newindex" and receiver then
				local run = 1
				while j + run <= #statements
					and statements[j + run].kind == "newindex"
					and statements[j + run].nest == statements[j].nest
					and string.match(statements[j + run].text, "^([%w_]+) = \"") == receiver
				do
					run += 1
				end
				if run >= 3 then
					merged[#merged + 1] = statements[j]
					merged[#merged + 1] = {
						text = string.format("--[[ ... %d more string assignments to %s (deobfuscator assembly) ]]", run - 1, receiver),
						kind = "note",
						nest = statements[j].nest,
					}
					j += run
					continue
				end
			end
			merged[#merged + 1] = statements[j]
			j += 1
		end
		statements = merged
	end
	end

do
	local merged: { Statement } = {}
	local j = 1
	while j <= #statements do
		if statements[j].kind == "call" and string.match(statements[j].text, "^table%.insert%(") then
			local run = 1
			while j + run <= #statements
				and statements[j + run].kind == "call"
				and string.match(statements[j + run].text, "^table%.insert%(") do
				run += 1
			end
			if run >= 3 then
				merged[#merged + 1] = statements[j]
				merged[#merged + 1] = {
					text = string.format("--[[ ... %d more table.insert calls (obfuscator data assembly) ]]", run - 1),
					kind = "note",
					nest = statements[j].nest,
				}
				j += run
				continue
			end
		end
		merged[#merged + 1] = statements[j]
		j += 1
	end
	statements = merged
end

do
	local merged: { Statement } = {}
	local j = 1
	while j <= #statements do
		if statements[j].kind == "call" and string.match(statements[j].text, "^setmetatable%(") then
			local run = 1
			while j + run <= #statements
				and statements[j + run].kind == "call"
				and string.match(statements[j + run].text, "^setmetatable%(") do
				run += 1
			end
			if run >= 3 then
				merged[#merged + 1] = statements[j]
				merged[#merged + 1] = {
					text = string.format("--[[ ... %d more setmetatable calls (VM setup) ]]", run - 1),
					kind = "note",
					nest = statements[j].nest,
				}
				j += run
				continue
			end
		end
		merged[#merged + 1] = statements[j]
		j += 1
	end
	statements = merged
end

do
	local filtered: { Statement } = {}
	for _, stmt in ipairs(statements) do

		if stmt.kind == "index" and string.match(stmt.text, "^local _ = function\(\) end") then
			continue
		end

		if stmt.kind == "newindex" and string.match(stmt.text, "= function\(\) end") then
			continue
		end
		filtered[#filtered + 1] = stmt
	end
	statements = filtered
end

do

	local nodeClass: { [number]: string } = {}
	for _, r in ipairs(trace.records) do
		if r.kind == "call" and r.detail and r.detail.constructor == true and type(r.detail.renderId) == "number" then
			if nodeClass[r.detail.renderId] == nil then
				nodeClass[r.detail.renderId] = tostring(r.detail.className or "Instance")
			end
		end
	end

	local connectedEvents: { [number]: { [string]: boolean } } = {}
	for _, s in ipairs(statements) do
		if type(s.connectBaseId) == "number" and type(s.connectEvent) == "string" then
			local set = connectedEvents[s.connectBaseId]
			if set == nil then
				set = {}
				connectedEvents[s.connectBaseId] = set
			end
			set[s.connectEvent] = true
		end
	end

	local usedNames: { [string]: number } = {}
	local nameOf: { [number]: string } = {}

	local boundName: { [number]: boolean } = {}
	local function isIdentifier(s: any): boolean
		return type(s) == "string" and string.match(s, "^[%a_][%w_]*$") ~= nil
	end
	local function nameFor(id: number): string
		local existing = nameOf[id]
		if existing ~= nil then
			return existing
		end
		local class = nodeClass[id] or "inst"
		local base = string.lower(string.sub(class, 1, 1)) .. string.sub(class, 2)
		base = string.gsub(base, "[^%w_]", "")
		if base == "" or string.match(base, "^%d") ~= nil then
			base = "inst" .. base
		end
		local count = usedNames[base]
		local name
		if count ~= nil then
			usedNames[base] = count + 1
			name = base .. tostring(count + 1)
		else
			usedNames[base] = 1
			name = base
		end
		nameOf[id] = name
		return name
	end

	local declared: { [number]: boolean } = {}
	local out: { Statement } = {}
	local function ensureDecl(id: number, nest: number)
		if declared[id] then
			return
		end
		declared[id] = true
		out[#out + 1] = {
			text = string.format("local %s = Instance.new(\"%s\")", nameFor(id), nodeClass[id] or "Instance"),
			kind = "newindex",
			nest = nest,
		}
	end

	for _, s in ipairs(statements) do
		local id = s.renderId

		if
			s.kind == "newindex"
			and type(id) ~= "number"
			and type(s.valueId) == "number"
			and nodeClass[s.valueId] ~= nil
			and string.match(s.text, "^[%a_][%w_]*%s*=%s") ~= nil
		then
			continue
		end
		if type(s.constructorClass) == "string" and type(id) == "number" then
			nodeClass[id] = nodeClass[id] or s.constructorClass
			if isIdentifier(s.writeKey) and nameOf[id] == nil and usedNames[s.writeKey :: string] == nil then

				local name = s.writeKey :: string
				nameOf[id] = name
				usedNames[name] = 1
				boundName[id] = true
				declared[id] = true
				out[#out + 1] = s
			else

				ensureDecl(id, s.nest)
			end
		elseif type(id) == "number" and nodeClass[id] ~= nil then
			ensureDecl(id, s.nest)
			if s.kind == "newindex" and type(s.writeKey) == "string" then
				local valueText = s.writeValue or "?"
				if type(s.valueId) == "number" and nodeClass[s.valueId] ~= nil then
					valueText = nameFor(s.valueId)
				end
				out[#out + 1] = {
					text = string.format("%s.%s = %s", nameFor(id), s.writeKey, valueText),
					kind = "newindex",
					nest = s.nest,
				}
			elseif s.kind == "index" and type(s.readKey) == "string" then

				local set = connectedEvents[id]
				if not (set ~= nil and set[s.readKey]) then
					out[#out + 1] = {
						text = string.format("local _ = %s.%s", nameFor(id), s.readKey),
						kind = "index",
						nest = s.nest,
					}
				end
			else
				out[#out + 1] = s
			end
		elseif type(s.connectBaseId) == "number" and nodeClass[s.connectBaseId] ~= nil then
			ensureDecl(s.connectBaseId, s.nest)
			out[#out + 1] = {
				text = string.format(
					"%s.%s:Connect(function() ... end)",
					nameFor(s.connectBaseId),
					s.connectEvent or "Event"
				),
				kind = "namecall",
				nest = s.nest,
			}
		else
			out[#out + 1] = s
		end
	end
	statements = out
end

	local loopBodyTexts: { [string]: boolean } = {}
	local loopCondTexts: { [string]: boolean } = {}
	do
		local function normalize(text: string): string

			return string.gsub(text, "%d+", "#")
		end

		local out: { Statement } = {}
		local i = 1
		local n = #statements
		while i <= n do
			local s = statements[i]
			if s.kind == "call" and string.match(s.text, "^task%.wait%(") then

				local cycleLen = 1
				while i + cycleLen <= n and not (statements[i + cycleLen].kind == "call"
					and string.match(statements[i + cycleLen].text, "^task%.wait%(")) do
					cycleLen += 1
					if cycleLen > 64 then break end
				end

				local reps = 1
				while i + reps * cycleLen <= n do
					local same = true
					for k = 0, cycleLen - 1 do
						local a = statements[i + k]
						local b = statements[i + k + reps * cycleLen]
						if b == nil or normalize(a.text) ~= normalize(b.text) or a.kind ~= b.kind then
							same = false
							break
						end
					end
					if same then
						reps += 1
					else
						break
					end
				end
				if reps >= 3 then
					out[#out + 1] = { text = "while true do", kind = "branch", nest = s.nest, opens = true }
					loopBodyTexts[normalize(s.text)] = true

					local function normNoVerdict(text: string): string
						local t = string.gsub(text, "%-%-didn?t %a+", "--VERDICT")
						t = string.gsub(t, "%d+", "#")
						return t
					end
					local emitStart = i + (reps - 1) * cycleLen
					local emitEnd = i + reps * cycleLen - 1
					local tailBase = i + reps * cycleLen

					local function normNoVerdict(text: string): string
						local t = string.gsub(text, "%-%-didn?t %a+", "--VERDICT")
						t = string.gsub(t, "%d+", "#")
						return t
					end
					if tailBase <= n then
						local want0 = statements[i]
						local got0 = statements[tailBase]
						if got0 ~= nil and want0 ~= nil and want0.kind == got0.kind
							and normNoVerdict(want0.text) == normNoVerdict(got0.text) then
							emitStart = tailBase
							local matched = 0
							while tailBase + matched <= n and matched < cycleLen do
								local w2 = statements[i + matched]
								local g2 = statements[tailBase + matched]
								if g2 == nil or w2 == nil or w2.kind ~= g2.kind
									or normNoVerdict(w2.text) ~= normNoVerdict(g2.text) then
									break
								end
								matched += 1
							end
							emitEnd = tailBase + matched - 1
						end
					end

					for probe = emitEnd + 1, math.min(emitEnd + cycleLen * 2, n) do
						local item = statements[probe]
						if item ~= nil and item.kind == "branch"
							and string.find(item.text, "--did ran", 1, true) ~= nil then
							emitEnd = probe
							if probe < n and statements[probe + 1].kind == "branch_end" then
								emitEnd = probe + 1
							end
							break
						end
					end
					for idx = emitStart, emitEnd do
						local item = statements[idx]
						out[#out + 1] = item
						loopBodyTexts[normalize(item.text)] = true
						if item.kind == "branch" then

							local condText = string.match(item.text, "^if%s+(.-)%s+then")
								or string.match(item.text, "^elseif%s+(.-)%s+then")
							if condText then
								loopCondTexts[normalize(condText)] = true
							end
						end
						if item.kind == "branch" and string.find(item.text, "--did ran", 1, true) then
							out[#out + 1] = { text = "break", kind = "note", nest = item.nest }
							loopBodyTexts[normalize("break")] = true
						end
					end
					out[#out + 1] = { text = "end", kind = "branch_end", nest = s.nest }
					i = emitEnd + 1
					continue
				end
			end
			out[#out + 1] = s
			i += 1
		end
		statements = out
	end

	local collapsed: { Statement } = {}
	local i = 1
	while i <= #statements do

		if statements[i].kind == "branch" then
			local run = 1
			while i + run * 2 <= #statements
				and statements[i + run * 2 - 1].kind == "branch_end"
				and statements[i + run * 2].kind == "branch"
				and statements[i + run * 2].text == statements[i].text
				and statements[i + run * 2].nest == statements[i].nest
				and statements[i + run * 2].branchId == statements[i].branchId do
				run += 1
			end
			local text = statements[i].text

			if run >= 2 then
				text = text .. string.format(" --[[ x%d ]]", run)
			end
			collapsed[#collapsed + 1] = {
				text = text,
				kind = "branch",
				nest = statements[i].nest,
				opens = statements[i].opens,
				elseIf = statements[i].elseIf,
				branchId = statements[i].branchId,
			}
			if run > 1 then

				i = i + run * 2 - 1
				continue
			end
			i += 1
			continue
		end

		if i + 2 <= #statements
			and statements[i + 1].kind == "index"
			and string.match(statements[i + 1].text, "^%-%-%[%[ .+ reads: .+ %]%]") ~= nil
			and statements[i + 2].text == statements[i].text
			and statements[i + 2].nest == statements[i].nest
		then
			local comment = statements[i + 1]
			local run = 1
			while i + run * 2 <= #statements
				and statements[i + run * 2].text == statements[i].text
				and statements[i + run * 2].nest == statements[i].nest
				and statements[i + run * 2].kind ~= "branch_end"
				and statements[i + run * 2 - 1].kind == "index"
				and statements[i + run * 2 - 1].text == comment.text do
				run += 1
			end
			if run >= 3 then
				local text = statements[i].text
				text = text .. string.format(" --[[ x%d ]]", run)
				collapsed[#collapsed + 1] = {
					text = text,
					kind = statements[i].kind,
					nest = statements[i].nest,
					opens = statements[i].opens,
					elseIf = statements[i].elseIf,
					branchId = statements[i].branchId,
				}

				collapsed[#collapsed + 1] = comment
				i = i + run * 2
				continue
			end
		end

		local run = 1

		while i + run <= #statements
			and statements[i + run].text == statements[i].text
			and statements[i + run].nest == statements[i].nest
			and statements[i + run].kind ~= "branch_end" do
			run += 1
		end
		local text = statements[i].text
		if run >= 3 then
			text = text .. string.format(" --[[ x%d ]]", run)
		end
		collapsed[#collapsed + 1] = {
			text = text,
			kind = statements[i].kind,
			nest = statements[i].nest,
			opens = statements[i].opens,
			elseIf = statements[i].elseIf,
			branchId = statements[i].branchId,
		}
		i += run
	end

	do
		local merged: { Statement } = {}
		local j = 1
		while j <= #collapsed do
			local s = collapsed[j]
			if s.kind == "branch" then

				local runStart = j
				local branchConds: { string } = {}
				local k = j
				while k <= #collapsed do
					local b = collapsed[k]
					if b.kind == "branch" then
						branchConds[#branchConds + 1] = b.text
						k += 1
					elseif b.kind == "branch_end" then

						k += 1
					else
						break
					end
				end			if #branchConds >= 2 then

				local dominated: { [string]: number } = {}
				local totalNumericBranches = 0
				for _, cond in ipairs(branchConds) do

					local var = string.match(cond, "if%s+([%w_]+)%s*[<>=~]+")
						or string.match(cond, "elseif%s+([%w_]+)%s*[<>=~]+")
					if var then

						local hasNumeric = string.match(cond, "[<>=~]+%s*0[xXbB][%da-fA-F]+")
							or string.match(cond, "[<>=~]+%s*%-?%d+[%.%d]*")
						if hasNumeric then
							dominated[var] = (dominated[var] or 0) + 1
							totalNumericBranches += 1
						end
					end
				end
				local maxVar, maxCount = "", 0
				for v, c in pairs(dominated) do
					if c > maxCount then maxVar, maxCount = v, c end
				end

				local dominatedEnough = maxCount >= 5 and maxCount >= math.floor(#branchConds * 0.6)
				local allNumericOnOneVar = maxCount >= 3 and totalNumericBranches >= #branchConds
					and maxCount >= math.floor(#branchConds * 0.8)
				if dominatedEnough or allNumericOnOneVar then

					merged[#merged + 1] = {
							text = string.format(
								"--[[ VM state dispatch: %d branches on '%s' (skipped) ]]",
								#branchConds, maxVar
							),
							kind = "note",
							nest = s.nest,
						}
						j = k
						continue
					end
				end
			end
			merged[#merged + 1] = s
			j += 1
		end
		collapsed = merged
	end

	do
		for _ = 1, 8 do
			local kept: { Statement } = {}
			local dropped = false
			local j = 1
			while j <= #collapsed do
				local s = collapsed[j]
				local next1 = collapsed[j + 1]
				if
					s.kind == "branch"
					and s.opens
					and not s.elseIf
					and next1 ~= nil
					and next1.kind == "branch_end"
					and string.find(s.text, ":IsA(", 1, true) ~= nil
				then
					j += 2
					dropped = true
					continue
				end
				kept[#kept + 1] = s
				j += 1
			end
			collapsed = kept
			if not dropped then
				break
			end
		end
	end

	do
		local function trivialGuard(text: string): boolean
			local body = string.match(text, "^if%s+(.-)%s+then%s+%-%-did ran$")
			if body == nil then
				return false
			end

			if string.match(body, '^[%w_]+%s*[=~<>]=%s*["\'%-%d]') or string.match(body, "^[%w_]+%s*[=~]=%s*nil$") then
				return true
			end

			if string.match(body, '^type[of]*%([%w_]+%)%s*[=~]=%s*["\']') then
				return true
			end
			return false
		end

		local kept: { Statement } = {}
		local j = 1
		while j <= #collapsed do
			local s = collapsed[j]
			local body = collapsed[j + 1]
			local close = collapsed[j + 2]
			if
				s.kind == "branch"
				and s.opens
				and not s.elseIf
				and body ~= nil
				and body.kind == "newindex"
				and close ~= nil
				and close.kind == "branch_end"
				and trivialGuard(s.text)
			then
				kept[#kept + 1] = body
				j += 3
				continue
			end
			kept[#kept + 1] = s
			j += 1
		end
		collapsed = kept
	end

	if #collapsed > maxStatements then
		truncated = true
		local head = math.min(maxStatements // 4, 2000)
		local tail = maxStatements - head
		local kept = table.create(maxStatements + 1)
		for j = 1, head do
			kept[j] = collapsed[j]
		end

		kept[head + 1] = {
			text = string.format("--[[ ??? %d statements dropped (decoder noise in the middle) ??? --]]", #collapsed - maxStatements),
			kind = "note",
			nest = collapsed[head].nest,
		}
		for j = 1, tail do
			kept[head + 1 + j] = collapsed[#collapsed - tail + j]
		end
		collapsed = kept
	end

	return collapsed, truncated, loopBodyTexts, loopCondTexts
end

export type Artifacts = {
	urls: { string },
	webhooks: { string },
	files: { string },
	clipboard: { string },
	keys: { string },
	remotes: { string },
}

local REMOTE_METHODS: { [string]: boolean } = {
	FireServer = true, FireClient = true, FireAllClients = true,
	InvokeServer = true, InvokeClient = true,
}

function Report.artifacts(trace: any): Artifacts
	local urls: { string } = {}
	local webhooks: { string } = {}
	local files: { string } = {}
	local clipboard: { string } = {}
	local keys: { string } = {}
	local remotes: { string } = {}
	local seenRemote: { [string]: boolean } = {}

	local seenUrl: { [string]: boolean } = {}
	local seenFile: { [string]: boolean } = {}

	local function noteUrl(url: string)
		if seenUrl[url] then
			return
		end
		seenUrl[url] = true
		if string.find(url, "discord.com/api/webhooks", 1, true)
			or string.find(url, "discordapp.com/api/webhooks", 1, true)
		then
			webhooks[#webhooks + 1] = url
		else
			urls[#urls + 1] = url
		end
	end

	for _, record in ipairs(trace.records) do
		if record.kind == "http" then
			noteUrl(record.expression)
		end

		if record.kind == "namecall" then
			local detail = record.detail
			local method = detail and detail.method
			if type(method) == "string" and REMOTE_METHODS[method] then
				local line = tostring(record.expression or "")
				if #line > 300 then
					line = string.sub(line, 1, 300) .. "..."
				end
				if not seenRemote[line] then
					seenRemote[line] = true
					remotes[#remotes + 1] = line
				end
			end
		end

		local detail = record.detail
		if detail then
			if detail.url then
				noteUrl(tostring(detail.url))
			end
			if detail.file and not seenFile[detail.file] then
				seenFile[detail.file] = true
				files[#files + 1] = tostring(detail.file)
			end
			if detail.clipboard then
				clipboard[#clipboard + 1] = tostring(detail.clipboard)
			end
		end

		local expression = record.expression
		for url in string.gmatch(expression, "https?://[%w%-%._~:/%?#@!%$&%(%)%*%+,;=%%]+") do
			noteUrl(url)
		end
		for candidate in string.gmatch(expression, "[%w%-_]{20,}") do
			keys[#keys + 1] = candidate
		end
	end

	table.sort(urls)
	table.sort(webhooks)
	table.sort(files)

	return { urls = urls, webhooks = webhooks, files = files, clipboard = clipboard, keys = keys, remotes = remotes }
end

export type RenderInput = {
	trace: any,
	stages: { any }?,
	outputs: { any }?,
	ok: boolean,
	err: string?,
	exhausted: boolean?,
	exhaustedReason: string?,
	detection: any?,

	elapsed: number?,

	inputBytes: number?,

	source: string?,

	explored: { any }?,

	vmTrace: { any }?,

	vmTraceCapped: boolean?,

	undefinedGlobals: { { name: string, count: number } }?,

	nilCulprit: string?,
}

local function stripReportComments(lines: { string }, sourceLines: { [number]: boolean }): string
	local out: { string } = {}
	for i, text in ipairs(lines) do
		if sourceLines[i] or i == 1 or text == HEADER then
			out[#out + 1] = text
		else
			local trimmed = text:match("^%s*(.*)$") or text
			if not trimmed:match("^%-%-") then
				out[#out + 1] = text
			end
		end
	end
	while #out > 0 and (out[1] or ""):match("^%s*$") do
		table.remove(out, 1)
	end
	local cleaned: { string } = {}
	local blank = false
	for _, text in ipairs(out) do
		if (text or ""):match("^%s*$") then
			if blank then
				continue
			end
			blank = true
		else
			blank = false
		end
		cleaned[#cleaned + 1] = (text:gsub("%s+$", ""))
	end
	return table.concat(cleaned, "\n")
end

function Report.render(input: RenderInput, options: Options?): string
	local settings = options or {}
	local maxStatements = settings.maxStatements or 20000
	local includeOps = if settings.includeOps == nil then true else settings.includeOps
	local includeStages = if settings.includeStages == nil then true else settings.includeStages
	local includeBranches = if settings.includeBranches == nil then true else settings.includeBranches
	local exploreBranches = if settings.exploreBranches == nil then true else settings.exploreBranches

	local notes = if settings.notes == nil then false else settings.notes

	local lines: { string } = {}

	local sourceLines: { [number]: boolean } = {}
	local function emit(text: string, isSource: boolean?)
		lines[#lines + 1] = text
		if isSource then
			sourceLines[#lines] = true
		end
	end
	emit(HEADER)

	local stamp = math.floor(os.clock() * 1000000) % 1000000000
	local stampChars = "0123456789abcdef"
	local stampStr = ""
	for _ = 1, 8 do
		stampStr = string.sub(stampChars, (stamp % 16) + 1, (stamp % 16) + 1) .. stampStr
		stamp = math.floor(stamp / 16)
	end
	emit("-- run id " .. stampStr)

	local degraded = (not input.ok) or input.exhausted == true
	if degraded then
		emit(RUNTIME_WARNING)
	end
	if input.err then
		emit("-- runtime error: " .. tostring(input.err))

		local errText = tostring(input.err)
		local isNilDeath = string.find(errText, "a nil value", 1, true) ~= nil
			or (string.find(errText, "attempt to ", 1, true) ~= nil and string.find(errText, "nil", 1, true) ~= nil)
		if isNilDeath then
			if input.nilCulprit then
				emit("--   nothing defines the global `" .. tostring(input.nilCulprit) .. "`; that is the nil the script used")
			else
				emit("--   the nil did not come from a global -- it was a table field or a call that returned nothing")
			end
			local others = {}
			for _, entry in ipairs(input.undefinedGlobals or {}) do
				if entry.name ~= input.nilCulprit and #others < 6 then
					others[#others + 1] = entry.name .. " (x" .. tostring(entry.count) .. ")"
				end
			end
			if #others > 0 then
				emit("--   other globals it expected but never found: " .. table.concat(others, ", "))
			end
		end
	end

	emit("")

	local statements, truncated, primaryLoopTexts, primaryLoopConds = reconstruct(input.trace, maxStatements, includeBranches)
	local function normalizeForLoop(text: string): string
		return string.gsub(text, "%d+", "#")
	end

	do
		local out: { Statement } = {}
		for i = 1, #statements do
			local s = statements[i]
			if s.kind == "newindex" then
				local target, value = string.match(s.text, "^([%w_]+) = (.+)$")
				if target and target ~= "_" and value and string.find(value, "(", 1, true) then

					local alreadyLocal = false
					for j = math.max(1, #out - 2), #out do
						if out[j] and string.match(out[j].text, "^local " .. target .. " =") then
							alreadyLocal = true
							break
						end
					end
					if not alreadyLocal then
						out[#out + 1] = {
							text = "local " .. target .. " = " .. value,
							kind = "newindex",
							nest = s.nest,
						}
						continue
					end
				end
			end
			out[#out + 1] = s
		end
		statements = out
	end

	do
		local out: { Statement } = {}
		local i = 1
		while i <= #statements do
			local s = statements[i]
			if s.kind == "index" and string.match(s.text, "^local _ = ") then
				local readExpr = string.match(s.text, "^local _ = (.+)$")
				local nxt = statements[i + 1]
				if nxt then

					if (nxt.kind == "namecall" or nxt.kind == "call") and readExpr then
						local callExpr = nxt.expression or ""
						if string.find(callExpr, readExpr, 1, true) == 1 then

							i += 1
							continue
						end
					end

					if nxt.kind == "newindex" and readExpr then
						local target, value = string.match(nxt.text, "^([%w_]+) = (.+)$")
						if target and target ~= "_" and value then
							local normR = string.gsub(readExpr, "%s+", "")
							local normV = string.gsub(value, "%s+", "")
							if normR == normV then
								out[#out + 1] = {
									text = "local " .. target .. " = " .. readExpr,
									kind = "newindex",
									nest = s.nest,
								}
								i += 2
								continue
							end
						end
					end
				end
			end
			out[#out + 1] = s
			i += 1
		end
		statements = out
	end

	do
		local out: { Statement } = {}
		local seen: { [string]: boolean } = {}
		for _, s in ipairs(statements) do

			if s.kind == "branch" or s.kind == "branch_end" or s.kind == "note" or s.kind == "output" then
				out[#out + 1] = s
				continue
			end
			local key = s.text
			if not seen[key] then
				seen[key] = true
				out[#out + 1] = s
			end
		end
		statements = out
	end

	local function renderStatements(list: { Statement }): { string }
		local out: { string } = {}
		local lastNest = list[1] and list[1].nest
		local depth = 0
		for _, statement in ipairs(list) do
			if statement.nest ~= lastNest then
				out[#out + 1] = ""
				lastNest = statement.nest
			end
			local indent = depth
			if (statement.kind == "branch" and statement.elseIf) or statement.kind == "branch_end" then
				indent = math.max(0, depth - 1)
			end
			out[#out + 1] = string.rep("  ", math.min(indent, 8)) .. statement.text
			if statement.kind == "branch" and statement.opens then
				depth += 1
			elseif statement.kind == "branch_end" then
				depth = math.max(0, depth - 1)
			end
		end
		return out
	end

	local function exploredFresh(entry: any, seenText: { [string]: boolean }): ({ Statement }?)
		if primaryLoopConds[normalizeForLoop(tostring(entry.cond))] then
			return nil
		end
		local altStatements = reconstruct(entry.trace, maxStatements, includeBranches)
		if primaryLoopTexts and next(primaryLoopTexts) ~= nil then
			local allLoop, anyStmt = true, false
			for _, statement in ipairs(altStatements) do
				if statement.kind == "branch" or statement.kind == "branch_end" then
					continue
				end
				anyStmt = true
				if not primaryLoopTexts[normalizeForLoop(statement.text)] then
					allLoop = false
				end
			end
			if anyStmt and allLoop then
				return nil
			end
		end
		local fresh: { Statement } = {}
		for _, statement in ipairs(altStatements) do
			if statement.kind == "branch" then
				fresh[#fresh + 1] = { text = branchKey(statement.text), kind = "branch", nest = statement.nest, opens = statement.opens, elseIf = statement.elseIf, branchId = statement.branchId }
				continue
			elseif statement.kind == "branch_end" then
				fresh[#fresh + 1] = statement
				continue
			end
			if not seenText[statement.text] then
				seenText[statement.text] = true
				fresh[#fresh + 1] = statement
			end
		end
		local hasBody = false
		for _, statement in ipairs(fresh) do
			if statement.kind ~= "branch" and statement.kind ~= "branch_end" then
				hasBody = true
				break
			end
		end
		if not hasBody then
			return nil
		end

		for _ = 1, 8 do
			local kept: { Statement } = {}
			local dropped = false
			local j = 1
			while j <= #fresh do
				local s = fresh[j]
				local next1 = fresh[j + 1]
				if s.kind == "branch" and s.opens and not s.elseIf and next1 ~= nil and next1.kind == "branch_end" then
					j += 2
					dropped = true
					continue
				end
				kept[#kept + 1] = s
				j += 1
			end
			fresh = kept
			if not dropped then
				break
			end
		end

		local stillHasBody = false
		for _, statement in ipairs(fresh) do
			if statement.kind ~= "branch" and statement.kind ~= "branch_end" then
				stillHasBody = true
				break
			end
		end
		return if stillHasBody then fresh else nil
	end

	local foldedEntries: { [number]: boolean } = {}
	if includeOps and exploreBranches and input.explored and #input.explored > 0 then

		local function matchEnd(list: { Statement }, openIdx: number): number?
			local depth = 0
			for k = openIdx, #list do
				local st = list[k]
				if st.kind == "branch" and st.opens then
					depth += 1
				elseif st.kind == "branch_end" then
					depth -= 1
					if depth == 0 then
						return k
					end
				end
			end
			return nil
		end

		local seenText: { [string]: boolean } = {}
		for _, statement in ipairs(statements) do
			seenText[statement.text] = true
			if statement.kind == "branch" then
				seenText[branchKey(statement.text)] = true
			end
		end

		for entryIdx, entry in ipairs(input.explored) do
			local fresh = exploredFresh(entry, seenText)
			if fresh == nil then
				continue
			end

			local head = fresh[1]
			if head.kind ~= "branch" or not head.opens or head.elseIf or head.branchId == nil then
				continue
			end
			local headEnd = matchEnd(fresh, 1)
			if headEnd ~= #fresh or headEnd < 3 then
				continue
			end

			local ifIdx: number? = nil
			local matches = 0
			for i, st in ipairs(statements) do
				if st.kind == "branch" and st.opens and not st.elseIf and st.branchId == head.branchId then
					matches += 1
					ifIdx = i
				end
			end
			if matches ~= 1 or ifIdx == nil then
				continue
			end
			local endIdx = matchEnd(statements, ifIdx)
			if endIdx == nil then
				continue
			end
			local ifNest = statements[ifIdx].nest

			local function copyBody(): { Statement }
				local body: { Statement } = {}
				for k = 2, headEnd - 1 do
					local st = fresh[k]
					body[#body + 1] = { text = st.text, kind = st.kind, nest = ifNest, opens = st.opens, elseIf = st.elseIf, branchId = st.branchId, envRead = st.envRead }
					seenText[st.text] = true
				end
				return body
			end

			if entry.forced == true then

				local nextSt = statements[ifIdx + 1]
				if nextSt == nil or (nextSt.kind ~= "branch" and nextSt.kind ~= "branch_end") then
					continue
				end
				for offset, st in ipairs(copyBody()) do
					table.insert(statements, ifIdx + offset, st)
				end
				foldedEntries[entryIdx] = true
			else

				local elseIdx: number? = nil
				local elseBodyStart: number? = nil
				local hasNonEmptyElse = false
				local depth = 0
				for k = ifIdx, endIdx do
					local st = statements[k]
					if st.kind == "branch" and st.opens then
						depth += 1
					elseif st.kind == "branch_end" then
						depth -= 1
					end
					if depth == 1 and k > ifIdx and st.kind == "branch" and st.elseIf then
						elseIdx = k

						local nextK = k + 1
						if nextK <= endIdx then
							local nxt = statements[nextK]
							if nxt.kind == "branch" or nxt.kind == "branch_end" then
								elseBodyStart = nextK
							else
								hasNonEmptyElse = true
							end
						else
							hasNonEmptyElse = true
						end
						break
					end
				end
				if hasNonEmptyElse then

					continue
				end
				if elseIdx ~= nil and elseBodyStart ~= nil then

					local body = copyBody()
					for offset, st in ipairs(body) do
						table.insert(statements, elseBodyStart + offset - 1, st)
					end
				else

					local spliced: { Statement } = {
						{ text = "else", kind = "branch", nest = ifNest, opens = false, elseIf = true, branchId = head.branchId },
					}
					for _, st in ipairs(copyBody()) do
						spliced[#spliced + 1] = st
					end
					for offset, st in ipairs(spliced) do
						table.insert(statements, endIdx + offset - 1, st)
					end
				end
				foldedEntries[entryIdx] = true
			end
		end
	end

	if includeOps and #statements > 0 then
		for _, line in ipairs(renderStatements(statements)) do
			emit(line)
		end
	end

	if includeOps then
		type UiNode = {
			id: number,
			class: string,
			name: string?,
			parentId: number?,
			order: number,
			props: { { key: string, value: string } },
			connections: { string },
			children: { number },
		}
		local nodes: { [number]: UiNode } = {}
		local nodeOrder: { number } = {}

		local STRUCTURAL: { [string]: boolean } = { Parent = true, Name = true }
		for i, r in ipairs(input.trace.records) do
			local d = r.detail
			if d == nil then
				continue
			end
			if r.kind == "call" and d.constructor == true and type(d.renderId) == "number" then
				if nodes[d.renderId] == nil then
					nodes[d.renderId] = {
						id = d.renderId,
						class = tostring(d.className or "Instance"),
						order = i,
						props = {},
						connections = {},
						children = {},
					}
					nodeOrder[#nodeOrder + 1] = d.renderId
				end
			elseif r.kind == "newindex" and type(d.renderId) == "number" and nodes[d.renderId] ~= nil then
				local node = nodes[d.renderId]
				local key = if type(d.key) == "string" then d.key else nil
				local valueText = ""
				local eqPos = string.find(r.expression, " = ", 1, true)
				if eqPos then
					valueText = string.sub(r.expression, eqPos + 3)
				end
				if key == "Name" then
					node.name = string.match(valueText, "^\"(.*)\"$") or valueText
				elseif key == "Parent" then
					if type(d.valueId) == "number" then
						node.parentId = d.valueId
					end
				elseif key ~= nil and #node.props < 12 then
					node.props[#node.props + 1] = { key = key, value = valueText }
				end
			elseif r.kind == "namecall" and d.callback == true and type(d.baseId) == "number"
				and nodes[d.baseId] ~= nil and type(d.event) == "string"
			then
				local conns = nodes[d.baseId].connections
				conns[#conns + 1] = d.event
			end
		end

		if #nodeOrder > 0 then

			local roots: { number } = {}
			for _, id in ipairs(nodeOrder) do
				local node = nodes[id]
				local parentId = node.parentId
				if type(parentId) == "number" and nodes[parentId] ~= nil then
					table.insert(nodes[parentId].children, id)
				else
					roots[#roots + 1] = id
				end
			end

			emit("")
			emit("-- UI HIERARCHY")

			local MAX_LINES = 200
			local lineCount = 0
			local function propSummary(node: UiNode): string
				if #node.props == 0 then
					return ""
				end
				local parts: { string } = {}
				for _, p in ipairs(node.props) do
					parts[#parts + 1] = p.key .. " = " .. p.value
				end
				return "  { " .. table.concat(parts, ", ") .. " }"
			end
			local seen: { [number]: boolean } = {}
			local function walk(id: number, depth: number)
				if lineCount >= MAX_LINES or seen[id] then
					return
				end
				seen[id] = true
				local node = nodes[id]
				local indent = string.rep("  ", depth)
				local label = string.format("%s%s %s", indent, node.class,
					if node.name ~= nil then "\"" .. node.name .. "\"" else "(unnamed)")
				emit("-- " .. label .. propSummary(node))
				lineCount += 1
				for _, event in ipairs(node.connections) do
					if lineCount >= MAX_LINES then
						break
					end
					emit(string.format("-- %s.%s -> function", indent .. "  ", event))
					lineCount += 1
				end
				for _, childId in ipairs(node.children) do
					walk(childId, depth + 1)
				end
			end
			for _, id in ipairs(roots) do
				walk(id, 0)
			end
			if lineCount >= MAX_LINES then
				emit("--   ... hierarchy truncated ...")
			end
		end
	end

	local stages = input.stages
	local haveStages = stages ~= nil and #stages > 0

	if includeStages and haveStages then
		local loadstringStages = 0
		local bufferStages = 0
		local totalSourceBytes = 0
		local totalBufferBytes = 0
		local maxNest = 0
		local fetchUrls: { string } = {}
		for _, stage in ipairs(stages) do
			if type(stage) ~= "table" then continue end
			if stage.origin == "loadstring" then
				loadstringStages += 1
				if type(stage.source) == "string" then
					totalSourceBytes += #stage.source
				end
			elseif stage.origin == "buffer" then
				bufferStages += 1
				if type(stage.data) == "string" then
					totalBufferBytes += #stage.data
				end
			end
			if (tonumber(stage.nest) or 0) > maxNest then
				maxNest = tonumber(stage.nest) or 0
			end
		end

		if input.trace and input.trace.records then
			for _, record in ipairs(input.trace.records) do
				if record.kind == "http" and record.expression then
					fetchUrls[#fetchUrls + 1] = record.expression
				end
			end
		end
		local totalStages = loadstringStages + bufferStages
		if totalStages > 1 then
			emit("")
			local parts: { string } = {}
			if loadstringStages > 0 then
				parts[#parts + 1] = string.format("%d loadstring", loadstringStages)
			end
			if bufferStages > 0 then
				parts[#parts + 1] = string.format("%d program buffer(s)", bufferStages)
			end
			if #fetchUrls > 0 then
				parts[#parts + 1] = string.format("%d url(s) fetched", #fetchUrls)
			end
			emit("-- " .. table.concat(parts, ", ")
				.. " recovered (depth " .. maxNest .. "); full sources attached")
		end

		if totalStages >= 1 and not input.unrolledSource then
			local best: string? = nil
			local bestNest = -1
			local bestExecuted = false
			for _, stage in ipairs(stages) do
				if type(stage) == "table" and stage.origin == "loadstring"
					and type(stage.source) == "string" and #stage.source >= 40 then
					local src = stage.source

					local linesCount = 0
					for _ in string.gmatch(src, "\n") do linesCount += 1 end
					local avgLen = #src / math.max(linesCount, 1)

					local _, escapes = string.gsub(src, "\\%d%d%d", "")
					local escapeDensity = escapes / math.max(#src, 1)

					local vmBlob = avgLen > 2000 and linesCount < 30
					vmBlob = vmBlob or escapeDensity > 0.10

					local firstByte = string.byte(src, 1)
					local printable = firstByte ~= nil
						and (firstByte >= 0x20 or firstByte == 9 or firstByte == 10)

					if printable and not vmBlob then
						local nestN = tonumber(stage.nest) or 0
						local exec = stage.executed == true
						if nestN > bestNest or (nestN == bestNest and exec and not bestExecuted) then
							best = src
							bestNest = nestN
							bestExecuted = exec
						end
					end
				end
			end
			if best then
				emit("")
				emit("-- recovered source (deepest decoded stage)")
				if bestExecuted then
					emit("-- this stage actually ran inside the sandbox")
				end
				emit(best, true)
			end
		end
	end

	if includeOps and input.vmTrace and #input.vmTrace > 0 then
		local vm = input.vmTrace
		local function fmtVal(v: any): string
			local t = type(v)
			if t == "number" then
				return string.format("%d", v)
			elseif t == "string" then
				return Serializer.stringLiteral(v)
			elseif t == "table" then
				return "{}"
			elseif t == "function" then
				return "fn"
			elseif v == nil then
				return "-"
			end
			return tostring(v)
		end
		emit("")
		emit("-- vm trace:")
		local shown = math.min(#vm, 40)
		for i = 1, shown do
			local st = vm[i]
			emit(string.format(
				"-- %06d  op %-4s  a=%s b=%s c=%s d=%s e=%s",
				i,
				tostring(st.op),
				fmtVal(st.a),
				fmtVal(st.b),
				fmtVal(st.c),
				fmtVal(st.d),
				fmtVal(st.e)
			))
		end
		if #vm > shown then
			emit(string.format("-- ... %d more states ...", #vm - shown))
		end

		local histo: { [any]: number } = {}
		for _, st in ipairs(vm) do
			local op = st.op or "?"
			histo[op] = (histo[op] or 0) + 1
		end
		local ops: { any } = {}
		for op in pairs(histo) do
			ops[#ops + 1] = op
		end
		table.sort(ops, function(x, y)
			return histo[x] > histo[y]
		end)
		local parts: { string } = {}
		for i = 1, math.min(#ops, 12) do
			parts[#parts + 1] = tostring(ops[i]) .. "x" .. tostring(histo[ops[i]])
		end
		emit("-- opcodes executed: " .. table.concat(parts, ", "))

		local totalStates = #vm
		local patterns: { string } = {}

		for _, entry in ipairs(ops) do
			if histo[entry] > 100 then
				local incrementCount = 0
				local lastVal: number? = nil
				for _, st in ipairs(vm) do
					if st.op == entry then
						local aVal = type(st.a) == "number" and st.a or nil
						if aVal and lastVal and aVal == lastVal + 1 then
							incrementCount += 1
						end
						lastVal = aVal
					end
				end
				if incrementCount > histo[entry] * 0.5 then
					patterns[#patterns + 1] = string.format(
						"opcode %s: likely XOR/decode loop (%d iterations with incrementing register)",
						tostring(entry), incrementCount
					)
				end
			end
		end

		for _, entry in ipairs(ops) do
			if histo[entry] > 50 then
				local stringCount = 0
				for _, st in ipairs(vm) do
					if st.op == entry then
						if type(st.b) == "string" or type(st.c) == "string" then
							stringCount += 1
						end
					end
				end
				if stringCount > histo[entry] * 0.3 then
					patterns[#patterns + 1] = string.format(
						"opcode %s: string operations (%d calls with string values)",
						tostring(entry), stringCount
					)
				end
			end
		end

		for _, entry in ipairs(ops) do
			if histo[entry] > 20 then
				local funcCount = 0
				for _, st in ipairs(vm) do
					if st.op == entry then
						if type(st.a) == "function" or type(st.b) == "function" then
							funcCount += 1
						end
					end
				end
				if funcCount > histo[entry] * 0.5 then
					patterns[#patterns + 1] = string.format(
						"opcode %s: function calls (%d invocations)",
						tostring(entry), funcCount
					)
				end
			end
		end

		for _, entry in ipairs(ops) do
			if histo[entry] > 10 then
				local tableCount = 0
				for _, st in ipairs(vm) do
					if st.op == entry then
						if type(st.a) == "table" or type(st.b) == "table" then
							tableCount += 1
						end
					end
				end
				if tableCount > histo[entry] * 0.8 then
					patterns[#patterns + 1] = string.format(
						"opcode %s: table construction (%d allocations)",
						tostring(entry), tableCount
					)
				end
			end
		end

		if #patterns > 0 then
			emit("-- detected patterns:")
			for _, pattern in ipairs(patterns) do
				emit("--   " .. pattern)
			end
		end

		local uniqueOpcodes = 0
		for _ in pairs(histo) do uniqueOpcodes += 1 end
		emit(string.format("-- execution profile: %d unique opcodes across %d states", uniqueOpcodes, totalStates))

		local tailOps: { any } = {}
		local tailStart = math.max(1, #vm - 2000 + 1)
		for i = tailStart, #vm do
			tailOps[#tailOps + 1] = vm[i].op
		end
		local tn = #tailOps
		local period, reps = nil, 0
		for p = 1, math.min(64, math.floor(tn / 4)) do
			local aligned = true
			for i = tn - p, tn do
				if tailOps[i] ~= tailOps[i - p] then
					aligned = false
					break
				end
			end
			if aligned then
				local count = 0
				local idx = tn
				while idx - p >= 1 and tailOps[idx] == tailOps[idx - p] do
					idx -= 1
					count += 1
				end
				count = math.floor(count / p)
				if count >= 4 then
					period, reps = p, count
					break
				end
			end
		end
		if period and reps then
			local cycle: { string } = {}
			for i = 1, period do
				cycle[#cycle + 1] = tostring(tailOps[tn - period + i])
			end
			emit(string.format(
				"-- tight loop detected: op cycle (%s) repeated %d+ times -- this is usually why the run exceeded its budget",
				table.concat(cycle, ", "),
				reps
			))
		end
		if input.vmTraceCapped then
			emit(string.format("-- trace capped at %d states", #vm))
		end
	end

	if includeOps and includeBranches then
		local guessed: { { expr: string, outcome: string, count: number } } = {}
		local seenGuess: { [string]: number } = {}
		for _, record in ipairs(input.trace.records) do
			if record.kind ~= "op" then
				continue
			end
			local detail = record.detail
			if detail == nil or detail.concrete ~= false then
				continue
			end
			local expr = string.gsub(tostring(record.expression), "[\r\n\t]+", " ")
			if #expr > 140 then
				expr = string.sub(expr, 1, 140) .. "..."
			end

			local hits = tonumber(detail.repeats) or 1
			local at = seenGuess[expr]
			if at then
				guessed[at].count += hits
			else
				seenGuess[expr] = #guessed + 1
				guessed[#guessed + 1] = {
					expr = expr,
					outcome = tostring(detail.outcome),
					count = hits,
				}
			end
		end
		if #guessed > 0 then
			emit("")
			emit(string.format("-- %d comparison(s) decided by the sandbox (an operand was unknown):", #guessed))
			local GUESS_CAP = 40
			for i = 1, math.min(#guessed, GUESS_CAP) do
				local entry = guessed[i]
				local times = if entry.count > 1 then string.format(" x%d", entry.count) else ""
				emit(string.format("--   %s -> %s%s", entry.expr, entry.outcome, times))
			end
			if #guessed > GUESS_CAP then
				emit(string.format("--   ... %d more", #guessed - GUESS_CAP))
			end
			emit("-- a real executor may answer these differently; the explored-branch")
			emit("-- sections below show what runs on the other side.")
		end
	end

	if includeOps and exploreBranches and input.explored and #input.explored > 0 then
		local seenText: { [string]: boolean } = {}

		local function dedupKey(text: string): string
			return (string.gsub(text, "^local%s+", ""))
		end
		for _, statement in ipairs(statements) do
			seenText[statement.text] = true
			seenText[dedupKey(statement.text)] = true
			if statement.kind == "branch" then

				seenText[branchKey(statement.text)] = true
			end
		end
	for entryIdx, entry in ipairs(input.explored) do

			if foldedEntries[entryIdx] then
				continue
			end

		if primaryLoopConds[normalizeForLoop(tostring(entry.cond))] then
			continue
		end
		local altStatements = reconstruct(entry.trace, maxStatements, includeBranches)

			if primaryLoopTexts and next(primaryLoopTexts) ~= nil then
				local allLoop = true
				local anyStmt = false
				for _, statement in ipairs(altStatements) do
					if statement.kind == "branch" or statement.kind == "branch_end" then
						continue
					end
					anyStmt = true
					if not primaryLoopTexts[normalizeForLoop(statement.text)] then
						allLoop = false
					end
				end
				if anyStmt and allLoop then
					continue
				end
			end
			local fresh: { Statement } = {}
			for _, statement in ipairs(altStatements) do

				if statement.kind == "branch" then
					local text = branchKey(statement.text)
					fresh[#fresh + 1] = { text = text, kind = "branch", nest = statement.nest, opens = statement.opens, elseIf = statement.elseIf, branchId = statement.branchId }
					continue
				elseif statement.kind == "branch_end" then
					fresh[#fresh + 1] = statement
					continue
				end
				local key = statement.text
				if not seenText[key] and not seenText[dedupKey(key)] then
					seenText[key] = true
					fresh[#fresh + 1] = statement
				end
			end

			for _ = 1, 8 do
				local kept: { Statement } = {}
				local removed = false
				local j = 1
				while j <= #fresh do
					local cur = fresh[j]
					local nxt = fresh[j + 1]
					if cur.kind == "branch" and cur.opens and not cur.elseIf and nxt ~= nil and nxt.kind == "branch_end" then
						j += 2
						removed = true
						continue
					end
					kept[#kept + 1] = cur
					j += 1
				end
				fresh = kept
				if not removed then
					break
				end
			end

			local hasBody = false
			for _, statement in ipairs(fresh) do
				if statement.kind ~= "branch" and statement.kind ~= "branch_end" then
					hasBody = true
					break
				end
			end
			if hasBody then
				emit("")
				local cond = string.gsub(tostring(entry.cond), "%]%]", "] ]")
				cond = string.gsub(cond, "[\r\n\t]+", " ")
				if #cond > 160 then
					cond = string.sub(cond, 1, 160) .. "..."
				end
				local verdict = if entry.taken then "truthy" else "falsy"
				emit(string.format("--[[ explored branch: %s (primary took %s, forced opposite) --]]", cond, verdict))
				for _, line in ipairs(renderStatements(fresh)) do
					emit(line)
				end
			end
		end
	end

	local hasObservable = false
	for _, s in ipairs(statements) do
		local t = s.text or ""
		local isProbe = t == ""
			or string.sub(t, 1, 2) == "--"
			or string.match(t, "getfenv%(%)$") ~= nil
			or string.match(t, "getgenv%(%)$") ~= nil
			or string.match(t, "getrenv%(%)$") ~= nil
			or string.match(t, "^local _ = ") ~= nil
			or string.match(t, "^_ = ") ~= nil
		if not isProbe then
			hasObservable = true
			break
		end
	end

	local haveVmTrace = input.vmTrace ~= nil and #input.vmTrace > 0
	if includeOps and not hasObservable and not haveStages and not haveVmTrace and not (exploreBranches and input.explored and #input.explored > 0) then
		emit("-- nothing observable happened; the script produced no environment effects")

		if input.source and #input.source > 0 and not haveStages then
			local okStatic, findings = pcall(require("./static").analyze, input.source)
			if okStatic and findings then

				local hasFindings = #findings.shells > 0 or #findings.urls > 0
					or #findings.webhooks > 0 or findings.stringCount > 0
				if hasFindings then
					emit("-- static extraction (nothing executed):")
					for _, shell in ipairs(findings.shells) do
						emit("--   shell: " .. shell)
					end
					if findings.loadstringRefs > 0 and #findings.shells == 0 then
						emit(string.format("--   %d loadstring/load call(s)", findings.loadstringRefs))
					end
					local urlsShown = 0
					for _, url in ipairs(findings.urls) do
						if urlsShown >= 5 then
							emit(string.format("--   ... %d more url(s)", #findings.urls - urlsShown))
							break
						end
						emit("--   url: " .. url)
						urlsShown += 1
					end
					if #findings.webhooks > 0 then
						emit(string.format("--   %d webhook endpoint(s)", #findings.webhooks))
					end
					if findings.stringCount > 0 then
						emit(string.format(
							"--   %d string literal(s), largest %d bytes",
							findings.stringCount,
							findings.largestString
						))
					end
				end
			end
		end
	end

	if includeOps and truncated then
		emit("")
		emit(string.format("-- output truncated at %d statements", maxStatements))
	end

	if includeOps and input.outputs and #input.outputs > 0 then
		local fresh: { any } = {}
		local bodyBlob: string? = nil
		for _, output in ipairs(input.outputs) do
			local text = output.text or ""
			local redundant = false
			if #text > 0 then
				if bodyBlob == nil then
					local texts: { string } = {}
					for _, statement in ipairs(statements) do
						texts[#texts + 1] = statement.text
					end
					bodyBlob = table.concat(texts, "\n")
				end
				redundant = string.find(bodyBlob, text, 1, true) ~= nil
			end
			if not redundant then
				fresh[#fresh + 1] = output
			end
		end
		if #fresh > 0 then
			emit("")
			emit("-- what script actually printed at runtime")
			for _, output in ipairs(fresh) do
				local channel = output.channel or "print"
				local text = output.text or ""
				if #text > 0 then
					emit("-- " .. text)
				else
					emit("-- " .. channel .. "()")
				end
			end
		end
	end

	if input.decryptedStrings and (input.decryptedStringCount or 0) > 0 then
		emit("")
		emit("-- decrypted strings (" .. tostring(input.decryptedStringCount) .. " captured)")

		local seen: { [string]: boolean } = {}
		local shown = 0
		for i = 1, math.min(input.decryptedStringCount or 0, 5000) do
			local s = input.decryptedStrings[i]
			if s and not seen[s] and #s > 0 then
				seen[s] = true
				shown += 1
				if shown > 200 then
					emit("-- ... and more")
					break
				end
				emit("-- \"" .. string.gsub(s, "[\"]", "\\\"") .. "\"")
			end
		end
	end

	if input.stringTable then
		local count = 0
		for _ in pairs(input.stringTable) do count += 1 end
		if count > 0 then
			emit("")
			emit("-- string table (" .. count .. " entries)")
			local shown = 0
			for hex, value in pairs(input.stringTable) do
				shown += 1
				if shown > 200 then
					emit("-- ... and more")
					break
				end
				emit("-- " .. hex .. " = \"" .. string.gsub(value, "[\"]", "\\\"") .. "\"")
			end
		end
	end

	if input.source and #input.source > 0 then
		local allSource = input.source

		if input.stages then
			for _, stage in ipairs(input.stages) do
				if type(stage) == "table" and type(stage.source) == "string" and #stage.source > 0 then
					allSource = allSource .. "\n" .. stage.source
				end
			end
		end
		local detections = AntiEnvDetect.analyze(allSource, input.trace and input.trace.records)
		if #detections > 0 then
			emit("")
			emit(string.format("-- anti-env detection: %d pattern(s) found", #detections))
			for _, det in ipairs(detections) do
				local icon = if det.severity == "critical" then "!!"
					elseif det.severity == "warn" then "!"
					else "i"
				local tag = if det.family ~= "generic" then string.format(" [%s]", det.family) else ""
				emit(string.format("--   [%s] %s%s: %s", icon, det.name, tag, det.description))
			end
		end
	end

	if input.unrolledSource then
		emit("")
		emit("-- unrolled multi-stage loader")
		emit(input.unrolledSource, true)
	end

	if not notes then
		return stripReportComments(lines, sourceLines)
	end
	return table.concat(lines, "\n")
end

function Report.log(trace: any): string
	local lines: { string } = { HEADER, "" }
	for _, record in ipairs(trace.records) do
		if not (record.detail and record.detail.undefinedGlobal) then
			lines[#lines + 1] = string.format(
				"%6d  %-10s %s",
				record.seq,
				record.kind,
				string.sub(record.expression, 1, 400)
			)
		end
	end
	if #lines == 2 then
		lines[#lines + 1] = "-- no events recorded"
	end
	return table.concat(lines, "\n")
end

return Report
