local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Blocklist = {}

export type Rules = {
	domains: { [string]: boolean },
	tlds: { [string]: boolean },
	labels: { [string]: boolean },
	ips: { [string]: boolean },
}

export type Status = {

	path: string?,

	error: string?,
	fileEntries: number,
	dropped: number,
	domains: number,
	tlds: number,
	labels: number,
	ips: number,
}

local function isIPv4(s: string): boolean
	local a, b, c, d = string.match(s, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then
		return false
	end
	for _, part in ipairs({ a, b, c, d }) do
		local n = tonumber(part)
		if not n or n > 255 or #part > 3 then
			return false
		end
	end
	return true
end

local function isIPv6(s: string): boolean
	local colons = 0
	for _ in string.gmatch(s, ":") do
		colons += 1
	end
	if colons < 2 then
		return false
	end
	return string.match(s, "^[%x:%.%%%w]+$") ~= nil
end

local function normalizeHost(host: any): string
	local h = string.lower(tostring(host or ""))
	h = string.gsub(h, "^%s+", "")
	h = string.gsub(h, "%s+$", "")
	local inner = string.match(h, "^%[([^%]]+)%]$")
	if inner then
		h = inner
	end
	h = string.gsub(h, "%.+$", "")
	return h
end

local function classifyEntry(raw: any): (string?, string?)
	local s = string.lower(tostring(raw or ""))
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	if s == "" then
		return nil, nil
	end

	s = string.gsub(s, "^%a[%w%+%.%-]*://", "")
	s = string.gsub(s, "^[^/@%s]*@", "")
	s = string.match(s, "^[^/%?#\\]*") or ""
	if s == "" then
		return nil, nil
	end

	local bracketed = string.match(s, "^%[([^%]]+)%]")
	if bracketed then
		s = bracketed
	else
		local colons = 0
		for _ in string.gmatch(s, ":") do
			colons += 1
		end
		if colons < 2 then
			s = string.gsub(s, ":%d+$", "")
		end
	end

	local leadingDot = string.sub(s, 1, 1) == "."
	s = string.gsub(s, "^%.+", "")
	s = string.gsub(s, "%.+$", "")
	if s == "" then
		return nil, nil
	end

	if isIPv4(s) or isIPv6(s) then
		return "ip", s
	end

	if not string.match(s, "^[%w%.%_%-]+$") then
		return nil, nil
	end
	if #s > 253 then
		return nil, nil
	end

	local parts: { string } = {}
	for label in string.gmatch(s, "[^%.]+") do
		parts[#parts + 1] = label
	end
	if #parts == 0 then
		return nil, nil
	end

	if #parts == 1 then
		if leadingDot then
			return "tld", parts[1]
		end
		return "label", parts[1]
	end
	return "domain", table.concat(parts, ".")
end

local function candidatePaths(): { string }
	local paths: { string } = {}
	local override = process.env.OMNIDBF_BLOCKLIST
	if type(override) == "string" and override ~= "" then
		paths[#paths + 1] = override
	end
	paths[#paths + 1] = "../badlinks.json"
	paths[#paths + 1] = "badlinks.json"
	paths[#paths + 1] = "../../badlinks.json"
	return paths
end

local function emptyStatus(): Status
	return {
		path = nil,
		error = nil,
		fileEntries = 0,
		dropped = 0,
		domains = 0,
		tlds = 0,
		labels = 0,
		ips = 0,
	}
end

local compiled: Rules? = nil
local loadStatus: Status = emptyStatus()

local function countKeys(set: { [string]: boolean }): number
	local n = 0
	for _ in pairs(set) do
		n += 1
	end
	return n
end

local function build(): Rules
	if compiled then
		return compiled
	end
	local built: Rules = { domains = {}, tlds = {}, labels = {}, ips = {} }

	local function add(entry: any): boolean
		local kind, value = classifyEntry(entry)
		if not kind or not value then
			return false
		end
		if kind == "domain" then
			built.domains[value] = true
		elseif kind == "tld" then
			built.tlds[value] = true
		elseif kind == "label" then
			built.labels[value] = true
		else
			built.ips[value] = true
		end
		return true
	end

	local fileEntries, dropped = 0, 0
	local loadedFrom: string? = nil
	local failure: string? = nil

	for _, candidate in ipairs(candidatePaths()) do
		local okRead, contents = pcall(fs.readFile, candidate)
		if not okRead or type(contents) ~= "string" then
			continue
		end
		local okDecode, decoded = pcall(serde.decode, "json", contents)
		if not okDecode or type(decoded) ~= "table" then

			failure = candidate .. ": " .. (if okDecode then "not a JSON list" else tostring(decoded))
			continue
		end

		local entries: { any }
		if decoded[1] ~= nil or next(decoded) == nil then
			entries = decoded
		else
			entries = {}
			for _, group in pairs(decoded) do
				if type(group) == "table" then
					for _, item in ipairs(group) do
						entries[#entries + 1] = item
					end
				else
					entries[#entries + 1] = group
				end
			end
		end

		for _, entry in ipairs(entries) do
			if type(entry) ~= "string" then
				dropped += 1
			elseif add(entry) then
				fileEntries += 1
			else
				dropped += 1
			end
		end
		loadedFrom = candidate
		failure = nil
		break
	end

	if not loadedFrom and not failure then
		failure = "not found (looked in " .. table.concat(candidatePaths(), ", ") .. ")"
	end

	loadStatus = {
		path = loadedFrom,
		error = failure,
		fileEntries = fileEntries,
		dropped = dropped,
		domains = countKeys(built.domains),
		tlds = countKeys(built.tlds),
		labels = countKeys(built.labels),
		ips = countKeys(built.ips),
	}
	compiled = built
	return built
end

function Blocklist.check(host: any): (boolean, string?, string?)
	local table_ = build()
	local h = normalizeHost(host)
	if h == "" then
		return true, "empty host", "malformed"
	end

	if isIPv4(h) or isIPv6(h) then
		if table_.ips[h] then
			return true, h, "ip"
		end
		return false, nil, nil
	end

	local labels: { string } = {}
	for label in string.gmatch(h, "[^%.]+") do
		labels[#labels + 1] = label
	end
	if #labels == 0 then
		return true, "malformed host", "malformed"
	end

	local last = labels[#labels]
	if table_.tlds[last] then
		return true, "." .. last, "tld"
	end
	for _, label in ipairs(labels) do
		if table_.labels[label] then
			return true, label, "label"
		end
	end
	for i = 1, #labels do
		local suffix = table.concat(labels, ".", i)
		if table_.domains[suffix] then
			return true, suffix, "domain"
		end
	end
	return false, nil, nil
end

function Blocklist.status(): Status
	build()
	return loadStatus
end

function Blocklist.summary(): string
	local s = Blocklist.status()
	if s.error then
		return string.format(
			"blocklist UNAVAILABLE (%s) -- only the built-in service list is in force, "
				.. "which is a deployment problem",
			s.error
		)
	end
	return string.format(
		"blocklist loaded from %s: %d entries -> %d domains, %d tlds, %d labels, %d ips (%d dropped)",
		tostring(s.path), s.fileEntries, s.domains, s.tlds, s.labels, s.ips, s.dropped
	)
end

function Blocklist.reload()
	compiled = nil
	loadStatus = emptyStatus()
end

Blocklist.classifyEntry = classifyEntry
Blocklist.normalizeHost = normalizeHost

return Blocklist
