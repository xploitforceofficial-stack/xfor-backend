	Blocklist unit tests: run with `lune run tests/blocklist` from `envlogger/`.

	The point of these is parity. `security.js` and `blocklist.luau` classify the
	same file and must agree, because a rule that behaves differently on the two
	sides makes the whole list untestable
	bot let a host through. `../tmp/blocklisttest.js` diffs the two classifiers
	entry-by-entry over the whole file (it drives `tests/blocklist_dump.luau` to get
	this side's answers); this file checks the semantics.
]]

local Blocklist = require("../src/env/blocklist")

local pass, fail = 0, 0
local function check(name: string, condition: boolean, extra: string?)
	if condition then
		pass += 1
		print("  ok   " .. name)
	else
		fail += 1
		print("  FAIL " .. name .. (if extra then "  <- " .. extra else ""))
	end
end

local function blocked(host: string): boolean
	local isBlocked = Blocklist.check(host)
	return isBlocked
end

local function ruleFor(host: string): string
	local _, rule, kind = Blocklist.check(host)
	return tostring(kind) .. ":" .. tostring(rule)
end

local status = Blocklist.status()
check("badlinks.json was found", status.error == nil, tostring(status.error))
check("it holds thousands of entries", status.fileEntries > 4000, tostring(status.fileEntries))
check("most entries are domain rules", status.domains > 4000, tostring(status.domains))
print("       " .. Blocklist.summary())

local function classify(entry: string): string
	local kind, value = Blocklist.classifyEntry(entry)
	return tostring(kind) .. ":" .. tostring(value)
end

check("a plain domain is a domain rule", classify("grabify.link") == "domain:grabify.link", classify("grabify.link"))
check("a scheme is stripped", classify("https://grabify.link") == "domain:grabify.link", classify("https://grabify.link"))
check("a path is stripped", classify("khu3x.net/") == "domain:khu3x.net", classify("khu3x.net/"))
check("a deeper path is stripped", classify("funnyordie.com/topic/sex") == "domain:funnyordie.com", classify("funnyordie.com/topic/sex"))
check("credentials are stripped", classify("user:pw@evil.com") == "domain:evil.com", classify("user:pw@evil.com"))
check("a port is stripped", classify("evil.com:8080") == "domain:evil.com", classify("evil.com:8080"))
check("capitals are folded", classify("GraBify.Link") == "domain:grabify.link", classify("GraBify.Link"))
check("a leading dot makes a tld rule", classify(".gov") == "tld:gov", classify(".gov"))
check("a bare label makes a label rule", classify("eporner") == "label:eporner", classify("eporner"))
check("an IPv4 literal is an address rule", classify("216.55.186.22") == "ip:216.55.186.22", classify("216.55.186.22"))
check("a bracketed IPv6 keeps its colons", classify("[::1]") == "ip:::1", classify("[::1]"))
check("a lookalike-character entry is dropped", classify("\239\185\144\239\185\144") == "nil:nil", classify("\239\185\144\239\185\144"))
check("an empty entry is dropped", classify("") == "nil:nil", classify(""))
check("a trailing dot is dropped", classify("grabify.link.") == "domain:grabify.link", classify("grabify.link."))

check("a listed host is blocked", blocked("grabify.link"))
check("a subdomain of a listed host is blocked", blocked("a.b.grabify.link"))
check("the rule reported is the suffix, not the full name",
	ruleFor("a.b.grabify.link") == "domain:grabify.link", ruleFor("a.b.grabify.link"))
check("a same-suffix-different-domain host is NOT blocked", not blocked("notgrabify.link"))
check("a host that merely contains a rule as a substring is NOT blocked", not blocked("mygrabify.linkage.com"))
check("an unlisted host is allowed", not blocked("raw.githubusercontent.com"))
check("a trailing dot cannot evade a rule", blocked("grabify.link."))
check("capitals cannot evade a rule", blocked("GRABIFY.LINK"))
check("a label rule matches a whole label", blocked("eporner.com") or blocked("www.eporner.com"))
check("a label rule does not match a longer label", not blocked("theeporner.example.org"))
check("a tld rule matches any host under it", blocked("whatever.gov"))
check("a tld rule does not match the label elsewhere", not blocked("gov.example.com"))

check("an empty host is refused", blocked(""))
check("whitespace-only is refused", blocked("   "))

print("")
print(tostring(pass) .. " passed, " .. tostring(fail) .. " failed")
if fail > 0 then
	local process = require("@lune/process")
	process.exit(1)
end
