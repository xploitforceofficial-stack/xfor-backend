local Sanitize = {}

local INTERNAL_MODULES: { [string]: boolean } = {
	spy = true,
	sandbox = true,
	roblox = true,
	control = true,
	stdlib = true,
	serializer = true,
	datatypes = true,
	trace = true,
	report = true,
	instrument = true,
	services = true,
	workspace = true,
	main = true,

	commands = true,
	discord = true,
	runner = true,
	roles = true,
	settings = true,
	vault = true,
	gateway = true,
	slash = true,
	extract = true,
}

function Sanitize.paths(text: string): string
	local out = text
	out = string.gsub(out, "[A-Za-z]:\\[^:\n]*\\", "")
	out = string.gsub(out, "/[%w%._%-/]+/", "")
	return out
end

function Sanitize.internalLocation(text: string): string
	local module = string.match(text, "^([%w_]+):%d+: ")
	if module and INTERNAL_MODULES[module] then
		return string.gsub(text, "^[^:]+:%d+: ", "")
	end
	local chunk = string.match(text, "^([^:]-%.luau?):%d+: ")
	if chunk then
		return string.gsub(text, "^[^:]-%.luau?:%d+: ", "", 1)
	end
	return text
end

function Sanitize.tracebackLines(text: string): string
	return (string.gsub(text, "\n[%w_ %-%.%/\\\t]+:%d+[^\n]*", ""))
end

function Sanitize.message(text: any): string
	return Sanitize.internalLocation(Sanitize.tracebackLines(Sanitize.paths(tostring(text))))
end

local REPLACEMENT = "\239\191\189"

function Sanitize.utf8(s: string): string
	if utf8.len(s) ~= nil then
		return s
	end
	local parts: { string } = {}
	local i = 1
	local n = #s
	while i <= n do
		local count = utf8.len(s, i, n)
		if count ~= nil then

			parts[#parts + 1] = string.sub(s, i)
			break
		end
		local _, errpos = utf8.len(s, i, n)
		errpos = errpos or i
		if errpos > i then
			parts[#parts + 1] = string.sub(s, i, errpos - 1)
		end
		parts[#parts + 1] = REPLACEMENT

		i = errpos + 1
		while i <= n and utf8.len(s, i, i) == nil do

			i += 1
		end
	end
	return table.concat(parts)
end

local SECRET_SCRUBS: { string } = {}

function Sanitize.addSecret(value: any)
	if type(value) == "string" and #value >= 4 then
		SECRET_SCRUBS[#SECRET_SCRUBS + 1] = value
	end
end

function Sanitize.secrets(text: string): string
	local out = text
	for _, secret in ipairs(SECRET_SCRUBS) do
		out = string.gsub(out, secret, "<script_key>")
	end
	out = string.gsub(out, "mfa%.[%w%-]+", "[REDACTED]")
	out = string.gsub(out, "[MN][A-Za-z%d_%-]+%.[A-Za-z%d_%-]+%.[A-Za-z%d_%-]+", "[REDACTED]")
	out = string.gsub(out, "https?://[%w%.%-]*discord[%w%.%-]*/api/webhooks/[%d%A-Za-z]+/[%w%-]+", "[REDACTED]")
	out = string.gsub(out, "BOT_TOKEN=%S+", "BOT_TOKEN=[REDACTED]")
	out = string.gsub(out, "TOKEN=%S+", "TOKEN=[REDACTED]")
	out = string.gsub(out, "WEBHOOK=%S+", "WEBHOOK=[REDACTED]")
	out = string.gsub(out, "SECRET=%S+", "SECRET=[REDACTED]")
	out = string.gsub(out, "PASSWORD=%S+", "PASSWORD=[REDACTED]")
	out = string.gsub(out, "_*%.?ROBLOSECURITY%s*[=:]%s*%S+", "[REDACTED]")
	out = string.gsub(out, "(sk_live_[%w%d]+|sk_test_[%w%d]+|xox[bap]-[%w%-]+)", "[REDACTED]")
	return out
end

function Sanitize.jsonSafe(value: any, seen: { [any]: boolean }?): any
	local kind = type(value)
	if kind == "string" then
		return Sanitize.utf8(value)
	end
	if kind ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return nil
	end
	seen[value] = true
	local out: { [any]: any } = {}
	for k, v in pairs(value) do
		local key = if type(k) == "string" then Sanitize.utf8(k) else k
		out[key] = Sanitize.jsonSafe(v, seen)
	end
	seen[value] = nil
	return out
end

return Sanitize
