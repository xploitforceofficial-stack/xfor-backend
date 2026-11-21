export type Kind =
	"index"
	| "newindex"
	| "call"
	| "namecall"
	| "loadstring"
	| "http"
	| "output"
	| "return"
	| "error"
	| "branch"
	| "branch_end"
	| "op"
	| "note"

export type Record = {
	seq: number,
	kind: Kind,

	expression: string,

	nest: number,

	detail: { [string]: any }?,
}

export type Trace = {
	records: { Record },
	count: number,

	limit: number,
	dropped: number,
}

local Trace = {}
Trace.__index = Trace

local COLLAPSIBLE: { [string]: boolean } = {
	index = true,
	newindex = true,
	call = true,
	namecall = true,

	op = true,
}

export type Class = typeof(setmetatable({} :: Trace, Trace))

function Trace.new(limit: number?): Class
	return setmetatable({
		records = {},
		count = 0,
		limit = limit or 100000,
		dropped = 0,
	} :: Trace, Trace)
end

function Trace.push(self: Class, kind: Kind, expression: string, nest: number, detail: { [string]: any }?): number
	self.count += 1
	if self.count > self.limit then
		self.dropped += 1
		return self.count
	end
	local last = self.records[#self.records]
	if
		COLLAPSIBLE[kind]
		and last ~= nil
		and last.kind == kind
		and last.nest == nest
		and last.expression == expression
	then
		local repeats = 2
		if last.detail ~= nil then
			repeats = tonumber(last.detail.repeats) or 1
			repeats += 1
			last.detail.repeats = repeats
		else
			last.detail = { repeats = repeats }
		end
		return last.seq
	end
	self.records[#self.records + 1] = {
		seq = self.count,
		kind = kind,
		expression = expression,
		nest = nest,
		detail = detail,
	}
	return self.count
end

function Trace.ofKind(self: Class, kind: Kind): { Record }
	local out: { Record } = {}
	for _, record in ipairs(self.records) do
		if record.kind == kind then
			out[#out + 1] = record
		end
	end
	return out
end

function Trace.truncate(self: Class, seq: number)
	for i = #self.records, 1, -1 do
		if self.records[i].seq >= seq then
			self.records[i] = nil
		else
			break
		end
	end
	self.count = seq - 1
end

return Trace
