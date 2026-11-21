	Fixture, not a test: emits the Luau side's blocklist decisions as JSON so
	`tmp/blocklisttest.js` can diff them against `security.js`'s.

	Reads `tests/_probes.json` ({ entries = {...}, hosts = {...} }), written by the
	Node side just before it runs this, and prints one JSON object on stdout.
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Blocklist = require("../src/env/blocklist")

local probes = serde.decode("json", fs.readFile("tests/_probes.json"))

local classified: { [string]: string } = {}
for _, entry in ipairs(probes.entries or {}) do
	local kind, value = Blocklist.classifyEntry(entry)
	classified[entry] = if kind then kind .. ":" .. tostring(value) else "nil"
end

local verdicts: { [string]: string } = {}
for _, host in ipairs(probes.hosts or {}) do
	local isBlocked, rule, kind = Blocklist.check(host)
	verdicts[host] = string.format("%s|%s|%s", tostring(isBlocked), tostring(kind), tostring(rule))
end

print(serde.encode("json", {
	classified = classified,
	verdicts = verdicts,
	status = Blocklist.status(),
}))
