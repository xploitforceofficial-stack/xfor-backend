local Sandbox = require("../src/core/sandbox")

local passes, fails = 0, 0
local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passes += 1
	else
		fails += 1
		print("[FAIL] " .. name .. " :: " .. tostring(detail))
	end
end

local function attempt(url: string, guard: string)
	local source = 'local ok, err = pcall(function() return game:HttpGet("'
		.. url .. '") end)\n' .. guard
	return Sandbox.run(source, { timeout = 10, maxExplored = 0 })
end

local function heldNote(result: any, url: string): boolean
	if result == nil or result.trace == nil then
		return false
	end
	for _, record in ipairs(result.trace.records) do
		if record.kind == "note"
			and type(record.expression) == "string"
			and string.find(record.expression, "not sent", 1, true)
			and record.detail ~= nil
			and tostring(record.detail.url) == url
		then
			return true
		end
	end
	return false
end

local blocked = {
	{ "loopback literal", "http://127.0.0.1/x" },
	{ "localhost", "http://localhost/x" },
	{ "trailing-dot localhost", "http://localhost./x" },
	{ "decimal-encoded loopback", "http://2130706433/x" },
	{ "hex-encoded loopback", "http://0x7f000001/x" },
	{ "short-form loopback", "http://127.1/x" },
	{ "private 10/8", "http://10.0.0.5/x" },
	{ "private 172.16/12", "http://172.16.0.1/x" },
	{ "private 192.168/16", "http://192.168.1.1/x" },
	{ "link-local 169.254 (cloud metadata)", "http://169.254.169.254/latest/meta-data/" },
	{ "CGNAT 100.64/10", "http://100.64.0.1/x" },
	{ "multicast 224/4", "http://224.0.0.1/x" },
	{ "this-network 0.0.0.0", "http://0.0.0.0/x" },
	{ "non-http scheme", "ftp://example.com/file" },
	{ "ip-echo service", "https://api.ipify.org/?format=json" },
}
for _, case in ipairs(blocked) do

	local result = attempt(case[2], 'if ok then error("NOT-BLOCKED") end')
	local refused = result ~= nil and result.ok == true
	check(case[1] .. " blocked", refused,
		if result then "run err: " .. tostring(result.err) else "no result")
end

local held = {
	{ "a badlinks.json host", "https://grabify.link/abc" },
	{ "a discord webhook", "https://discord.com/api/webhooks/1/2" },
	{ "a versioned discord webhook", "https://discord.com/api/v10/webhooks/1/2" },
	{ "the telegram bot api", "https://api.telegram.org/bot123:abc/sendMessage" },
}
for _, case in ipairs(held) do
	local result = attempt(case[2], 'if not ok then error("RAISED: " .. tostring(err)) end')
	local ranClean = result ~= nil and result.ok == true
	check(case[1] .. " does not raise", ranClean,
		if result then "run err: " .. tostring(result.err) else "no result")
	check(case[1] .. " is recorded as not sent", ranClean and heldNote(result, case[2]),
		"no \"not sent\" note for " .. case[2])
end

local allowed = {
	{ "a raw github stage", "https://raw.githubusercontent.com/a/b/main/l.lua" },
	{ "a paste host", "https://pastebin.com/raw/abcd1234" },
	{ "a discord CDN attachment", "https://cdn.discordapp.com/attachments/1/2/loader.lua" },
	{ "discord itself, off the webhook path", "https://discord.com/api/v10/users/@me" },
}
for _, case in ipairs(allowed) do
	local result = attempt(case[2], 'if not ok then error("BLOCKED: " .. tostring(err)) end')
	local ranClean = result ~= nil and result.ok == true
	check(case[1] .. " allowed", ranClean,
		if result then "run err: " .. tostring(result.err) else "no result")
	check(case[1] .. " carries no refusal note", ranClean and not heldNote(result, case[2]),
		"unexpected \"not sent\" note for " .. case[2])
end

print(string.format("\nssrf: %d passed, %d failed", passes, fails))
if fails > 0 then
	error("ssrf spec failed")
end
