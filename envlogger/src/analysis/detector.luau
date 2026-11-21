local Detector = {}

export type Match = {
	name: string,
	score: number,

	evidence: { string },
}

export type Result = {

	name: string,
	confidence: "high" | "medium" | "low" | "none",
	score: number,
	evidence: { string },

	candidates: { Match },

	strategy: "loadstring" | "vm" | "hybrid" | "plain",

	version: string?,

	metrics: {
		bytes: number,
		lines: number,
		longestLine: number,
		printableRatio: number,
		escapeDensity: number,
	},
}

type Signature = {
	name: string,
	strategy: "loadstring" | "vm" | "hybrid",

	literals: { { text: string, weight: number, label: string } }?,

	patterns: { { pattern: string, weight: number, label: string } }?,

	custom: ((source: string, metrics: any) -> (number, string?))?,

	version: { pattern: string, label: string }?,
}

local SIGNATURES: { Signature } = {
	{
		name = "MoonSec V3",
		strategy = "vm",
		literals = {
			{ text = "This file was protected with MoonSec V3", weight = 60, label = "MoonSec V3 banner" },
			{ text = "MoonSec_StringsHiddenAttr", weight = 40, label = "MoonSec string attribute" },
			{ text = "moonsec", weight = 20, label = "moonsec reference" },
		},
		patterns = {

			{ pattern = "%(%[%[.-%]%]%):gsub%b()", weight = 35, label = "gsub self-assignment preamble" },

			{ pattern = "while%s+%w+%s*<%s*0?x?%x+%s+and%s+%w+%%0x%x+", weight = 30, label = "hex modulo dispatch loop" },
			{ pattern = "if%s+not%s+%w+%[%w+%]then%s+%w+%[%w+%]=0x1", weight = 25, label = "guard-table VM pattern" },
		},
		version = { pattern = "protected with MoonSec%s+V([%d%.]+)", label = "MoonSec version" },
	},
	{
		name = "MoonSec V1/V2",
		strategy = "loadstring",
		literals = {
			{ text = "MoonSec", weight = 30, label = "MoonSec reference" },
			{ text = "moonsec.dev", weight = 40, label = "MoonSec domain" },
			{ text = "Protected_by_MoonSecV2", weight = 60, label = "MoonSec V2 banner" },
		},
		patterns = {
			{ pattern = "\\108\\111\\97\\100", weight = 20, label = "escaped 'load' constant" },
			{ pattern = "Protected_by_MoonSecV?(%d)", weight = 20, label = "MoonSec V2 banner" },
		},
		version = { pattern = "Protected_by_MoonSecV?(%d+)", label = "MoonSec version" },
	},
	{
		name = "AquaByte",
		strategy = "hybrid",
		literals = {
			{ text = "protected by aquabyte", weight = 65, label = "AquaByte protection banner" },
			{ text = "protected using aquabyte", weight = 65, label = "AquaByte protection banner" },
			{ text = "aquabyte.dpdns.org", weight = 55, label = "AquaByte domain" },
			{ text = "dsc.gg/aquabyte", weight = 50, label = "AquaByte invite link" },
			{ text = "aquabyte", weight = 35, label = "AquaByte reference" },
		},
		patterns = {

			{ pattern = "^return%(%{RP=", weight = 30, label = "AquaByte table shell header" },
			{ pattern = "%}):%w+%(%)%(%.%.%.%)", weight = 25, label = "table-shell immediate invocation" },
		},
		custom = function(source: string, metrics: any): (number, string?)

			if string.sub(source, 1, 8) == "return({" and string.find(source, "%}):%w+%(%)%(%.%.%.%)") then
				return 20, "self-invoking table shell"
			end
			return 0, nil
		end,
	},
	{
		name = "LuaGuard",
		strategy = "hybrid",
		literals = {
			{ text = "luaguard.com", weight = 55, label = "LuaGuard domain" },
			{ text = "luaguard", weight = 45, label = "LuaGuard reference" },
			{ text = "LuaGuard", weight = 40, label = "LuaGuard watermark" },
			{ text = "luaguard_", weight = 30, label = "LuaGuard prefix" },
		},
	},
	{
		name = "Yama",
		strategy = "hybrid",
		literals = {
			{ text = "yama", weight = 40, label = "Yama reference" },
			{ text = "yamascripts", weight = 45, label = "Yama scripts domain" },
		},
		patterns = {
			{ pattern = "--[%[=]*[ \n]*Yama", weight = 30, label = "Yama header comment" },
		},
	},
	{
		name = "Ecliptium",
		strategy = "vm",
		literals = {
			{ text = "ecliptium.com", weight = 55, label = "Ecliptium domain" },
			{ text = "ecliptium", weight = 45, label = "Ecliptium reference" },
		},
		patterns = {
			{ pattern = "ecl_%w+", weight = 25, label = "ecl_ prefix" },
		},
	},
	{
		name = "FlowGuard",
		strategy = "vm",
		literals = {
			{ text = "flowguard.xyz", weight = 55, label = "FlowGuard domain" },
			{ text = "flowguard", weight = 45, label = "FlowGuard reference" },
		},
	},
	{
		name = "XFuscator",
		strategy = "hybrid",
		literals = {
			{ text = "xfuscator", weight = 45, label = "XFuscator reference" },
			{ text = "xftest", weight = 35, label = "XFuscator test constant" },
			{ text = "xf_", weight = 25, label = "xf_ prefix" },
		},
	},
	{
		name = "SecureVoid",
		strategy = "hybrid",
		literals = {
			{ text = "securevoid", weight = 45, label = "SecureVoid reference" },
			{ text = "sv_", weight = 25, label = "sv_ prefix" },
		},
	},
	{
		name = "LuaCrypt",
		strategy = "hybrid",
		literals = {
			{ text = "luacrypt", weight = 45, label = "LuaCrypt reference" },
			{ text = "lucrypt", weight = 30, label = "LuaCrypt alias" },
		},
	},
	{
		name = "OxyGen",
		strategy = "vm",
		literals = {
			{ text = "oxygen", weight = 40, label = "OxyGen reference" },
			{ text = "oxygenscripts", weight = 45, label = "OxyGen scripts domain" },
			{ text = "oxy obfuscator", weight = 50, label = "Oxy obfuscator banner" },
		},
	},
	{
		name = "Krnl",
		strategy = "hybrid",
		literals = {
			{ text = "krnl", weight = 40, label = "Krnl reference" },
			{ text = "krnl.place", weight = 45, label = "Krnl domain" },
		},
	},
	{
		name = "Sirius",
		strategy = "vm",
		literals = {
			{ text = "sirius.menu", weight = 50, label = "Sirius domain" },
			{ text = "sirius", weight = 35, label = "Sirius reference" },
		},
	},
	{
		name = "NoMoreObfuscation",
		strategy = "vm",
		literals = {
			{ text = "nomoreobfuscation", weight = 45, label = "NoMoreObfuscation reference" },
			{ text = "nmo_", weight = 25, label = "nmo_ prefix" },
		},
	},
	{
		name = "Proxo",
		strategy = "hybrid",
		literals = {
			{ text = "proxo", weight = 40, label = "Proxo reference" },
		},
	},
	{
		name = "Eclipse",
		strategy = "hybrid",
		literals = {
			{ text = "eclipse obfuscator", weight = 50, label = "Eclipse obfuscator banner" },
			{ text = "eclipsescripts", weight = 45, label = "Eclipse scripts domain" },
		},
	},
	{
		name = "Luraph",
		strategy = "vm",
		literals = {
			{ text = "Luraph", weight = 60, label = "Luraph watermark" },
			{ text = "luraph.com", weight = 55, label = "Luraph domain" },
			{
				text = "(does your environment support load/loadstring?)",
				weight = 50,
				label = "Luraph environment probe",
			},
			{ text = "LPH_", weight = 35, label = "LPH_ macro prefix" },
			{ text = "lura.ph", weight = 45, label = "Luraph short domain" },
		},
		patterns = {
			{ pattern = "LPH_JIT", weight = 25, label = "LPH_JIT macro" },
			{ pattern = "LPH_NO_VIRTUALIZE", weight = 25, label = "LPH_NO_VIRTUALIZE macro" },

			{ pattern = "Luraph%s+Obfuscator%s+v%d", weight = 40, label = "Luraph version banner" },
		},
		version = { pattern = "Luraph%s+Obfuscator%s+v([%d%.]+)", label = "Luraph version" },
	},
	{
		name = "IronBrew2",
		strategy = "vm",
		literals = {
			{ text = "IronBrew", weight = 60, label = "IronBrew watermark" },
			{ text = "ironbrew", weight = 50, label = "ironbrew reference" },
		},
		patterns = {

			{ pattern = "local%s+%w+=string%.byte;?local%s+%w+=string%.char", weight = 25, label = "byte/char alias pair" },
			{ pattern = "\\3\\4\\5\\6\\7", weight = 20, label = "sequential escape table" },
		},
	},
	{
		name = "Prometheus",
		strategy = "loadstring",
		literals = {
			{ text = "prometheus.dev", weight = 55, label = "Prometheus domain" },
			{ text = "Prometheus", weight = 35, label = "Prometheus watermark" },
			{ text = "levno-plev", weight = 40, label = "Prometheus author tag" },
			{ text = "https://wearedevs.net/obfuscator", weight = 45, label = "WeAreDevs-branded Prometheus banner" },
		},
		patterns = {

			{ pattern = "%(%-?%d%d%d%d+%+%-?%d%d%d%d+%)", weight = 20, label = "arithmetic constant folding" },
			{ pattern = "%-%-%[%[.-%]%]%s*return%(function%(%.%.%.%)", weight = 25, label = "wrapped vararg entry" },

			{ pattern = "^return%(function%(%.%.%.%)local%s+%w+=%{%\"\\%d%d%d", weight = 25, label = "escaped string table header" },
		},
		version = { pattern = "v(%d+%.%d+%.%d+)%s+https://wearedevs", label = "WeAreDevs build" },
	},
	{
		name = "WeAreDevs",
		strategy = "loadstring",
		literals = {
			{ text = "wearedevs.net/obfuscator", weight = 60, label = "WeAreDevs obfuscator URL" },
			{ text = "wearedevs", weight = 45, label = "wearedevs reference" },
		},
		patterns = {
			{ pattern = "v%d%.%d%.%d%s+https://wearedevs", weight = 50, label = "versioned WeAreDevs banner" },

			{ pattern = "string%.char%b()", weight = 10, label = "string.char call" },
			{ pattern = "if%s*[%w_]+[%w_]*%s*then\n[%s\t]*loadstring", weight = 20, label = "loadstring in if block" },
		},
	},
	{
		name = "PSU / Xen",
		strategy = "vm",
		literals = {

			{ text = "psu.dev", weight = 60, label = "PSU domain" },
			{ text = "XenTeam", weight = 45, label = "Xen watermark" },
			{ text = "Obfuscated by PSU Obfuscator", weight = 75, label = "PSU banner" },
			{ text = "obfuscated using PSU Obfuscator", weight = 75, label = "PSU banner" },
		},
		version = { pattern = "PSU%s+Obfuscator%s+v?([%d%.]+%a?)", label = "PSU version" },
	},
	{
		name = "Luarmor",
		strategy = "vm",
		literals = {
			{ text = "luarmor", weight = 55, label = "Luarmor reference" },
			{ text = "LRM_", weight = 35, label = "LRM_ prefix" },
			{ text = "Luarmor", weight = 50, label = "Luarmor watermark" },
		},
	},
	{
		name = "Boronide",
		strategy = "vm",
		literals = {
			{ text = "boronide", weight = 55, label = "Boronide reference" },
			{ text = "Boronide", weight = 55, label = "Boronide watermark" },
			{ text = "herrtts obf, discord.gg/BZEjFbeUvk", weight = 50, label = "Boronide discord banner" },
		},
		version = { pattern = "herrtt's obfuscator, v([%d%.]+)", label = "Boronide build" },
	},
	{
		name = "77fuscator",
		strategy = "vm",
		literals = {
			{ text = "77fuscator", weight = 60, label = "77fuscator banner" },
		},
		version = { pattern = "77fuscator%s+([%d%.]+)", label = "77fuscator version" },
	},
	{
		name = "Hercules",
		strategy = "vm",
		literals = {
			{ text = "hercules-obfuscator.xyz", weight = 55, label = "Hercules domain" },
			{ text = "Obfuscated by Hercules", weight = 50, label = "Hercules banner" },
			{ text = "Hercules", weight = 35, label = "Hercules reference" },
		},
		version = { pattern = "Hercules%s+v([%d%.]+)", label = "Hercules version" },
	},
	{
		name = "LPS",
		strategy = "vm",
		literals = {
			{ text = "LPS", weight = 25, label = "LPS reference" },
		},
		patterns = {

			{ pattern = "%[%^%!%-uz%]", weight = 45, label = "LPS bit-pack gsub charset" },
		},
	},
	{
		name = "MoonVeil",
		strategy = "hybrid",
		literals = {
			{ text = "moonveil.cc", weight = 55, label = "MoonVeil domain" },
			{ text = "MoonVeil Obfuscator", weight = 55, label = "MoonVeil banner" },
			{ text = "MoonVeil", weight = 35, label = "MoonVeil reference" },
		},
		patterns = {

			{ pattern = "%}):M%(%.", weight = 30, label = ":M( entry pattern" },
			{ pattern = "%}):ta%(%.", weight = 30, label = ":ta( entry pattern" },

			{ pattern = "while%s+true%s+do%s+if%s+v>%s*0x", weight = 30, label = "MoonVeil dispatch state machine" },

			{ pattern = "if%s+v>%s*0x%x+%s+then", weight = 15, label = "hex dispatch branch" },

			{ pattern = "0b[01]+", weight = 10, label = "binary literal" },
		},
		custom = function(source: string, metrics: any): (number, string?)

			if string.sub(source, 1, 9) == "return({" and string.find(source, "%}:M%(") then
				return 25, "table shell with :M( entry"
			end
			if string.sub(source, 1, 9) == "return({" and string.find(source, "%}:ta%(") then
				return 25, "table shell with :ta( entry"
			end
			return 0, nil
		end,
		version = { pattern = "MoonVeil%s+Obfuscator%s+v([%d%.]+)", label = "MoonVeil version" },
	},
	{
		name = "Synapse Xen",
		strategy = "vm",
		literals = {
			{ text = "Synapse Xen", weight = 55, label = "Synapse Xen banner" },
			{ text = "Synapse GP", weight = 45, label = "Synapse GP credit" },
			{ text = "Xen", weight = 25, label = "Xen reference" },
		},
		version = { pattern = "Synapse%s+Xen%s+v([%d%.]+)", label = "Synapse Xen version" },
	},
	{
		name = "LuaObfuscator",
		strategy = "hybrid",
		literals = {
			{ text = "LuaObfuscator", weight = 50, label = "LuaObfuscator watermark" },
		},
		patterns = {

			{ pattern = "local%s+v0=string%.char;local%s+v1=string%.byte", weight = 40, label = "vN alias preamble" },
			{ pattern = "local%s+v0=tonumber;local%s+v1=string%.byte", weight = 40, label = "vN VM preamble" },
		},
	},
	{
		name = "IronBrew3",
		strategy = "vm",
		literals = {
			{ text = "ironbrew3", weight = 60, label = "IronBrew3 banner" },
			{ text = "ironbrew3:tm:", weight = 55, label = "IronBrew3 trademark banner" },
		},
		version = { pattern = "ironbrew3:tm:, v([%d%.]+)", label = "IronBrew3 version" },
	},
	{
		name = "wYnFuscate",
		strategy = "vm",
		literals = {
			{ text = "wYnFuscate", weight = 60, label = "wYnFuscate watermark" },
			{ text = "wynfuscate.com", weight = 55, label = "wYnFuscate domain" },
			{ text = "Protected by wYnFuscate", weight = 60, label = "wYnFuscate banner" },
		},
	},
}

local function computeMetrics(source: string)
	local bytes = #source
	local lines = 1
	local longestLine = 0
	local currentLine = 0
	local printable = 0
	local escapes = 0

	for index = 1, bytes do
		local byte = string.byte(source, index)
		if byte == 10 then
			lines += 1
			if currentLine > longestLine then
				longestLine = currentLine
			end
			currentLine = 0
		else
			currentLine += 1
		end
		if byte >= 32 and byte < 127 then
			printable += 1
		end
		if byte == 92 then
			escapes += 1
		end
	end
	if currentLine > longestLine then
		longestLine = currentLine
	end

	return {
		bytes = bytes,
		lines = lines,
		longestLine = longestLine,
		printableRatio = if bytes > 0 then printable / bytes else 1,
		escapeDensity = if bytes > 0 then escapes / bytes else 0,
	}
end

local function genericEvidence(source: string, metrics: any): { string }
	local found: { string } = {}

	if metrics.lines <= 3 and metrics.bytes > 5000 then
		found[#found + 1] = "entire payload on a single line"
	end
	if metrics.longestLine > 10000 then
		found[#found + 1] = string.format("longest line is %d chars", metrics.longestLine)
	end
	if metrics.escapeDensity > 0.05 then
		found[#found + 1] = string.format("%.1f%% escape sequences", metrics.escapeDensity * 100)
	end
	if string.find(source, "\\%d%d%d\\%d%d%d\\%d%d%d") then
		found[#found + 1] = "long decimal escape runs"
	end
	if string.find(source, "getfenv", 1, true) then
		found[#found + 1] = "getfenv usage"
	end
	if string.find(source, "loadstring", 1, true) or string.find(source, "\\108\\111\\97\\100", 1, true) then
		found[#found + 1] = "loadstring reference"
	end
	if string.find(source, "0x%x%x%x%x") then
		found[#found + 1] = "dense hex constants"
	end

	if string.find(source, "bit32%.bxor") and metrics.bytes > 2000 then
		found[#found + 1] = "bit32.bxor usage (VM bytecode)"
	end
	if string.find(source, "string%.byte") and string.find(source, "string%.char") then
		found[#found + 1] = "string.byte/char pair (bytecode decoder)"
	end
	if string.find(source, "while%s+true%s+do%s+if") and metrics.bytes > 5000 then
		found[#found + 1] = "while true do if dispatch loop"
	end
	if string.find(source, "newproxy") and string.find(source, "setmetatable") then
		found[#found + 1] = "newproxy+setmetatable (VM container)"
	end
	if string.find(source, "return%(%{" ) and string.find(source, "%}:\w+%(%)") then
		found[#found + 1] = "self-invoking table shell"
	end
	if string.find(source, "return%(function%%(%.)%%.%.%.%%)") or string.find(source, "return%%(function%%(%.%%.%.%%)") then
		found[#found + 1] = "vararg function entry"
	end
	if metrics.printableRatio < 0.5 and metrics.bytes > 1000 then
		found[#found + 1] = string.format("low printable ratio (%.0f%%)", metrics.printableRatio * 100)
	end

	return found
end

function Detector.detect(source: string): Result
	local metrics = computeMetrics(source)

	local lowered = string.lower(source)

	local candidates: { Match } = {}

	for _, signature in ipairs(SIGNATURES) do
		local score = 0
		local evidence: { string } = {}

		if signature.literals then
			for _, literal in ipairs(signature.literals) do
				if string.find(lowered, string.lower(literal.text), 1, true) then
					score += literal.weight
					evidence[#evidence + 1] = literal.label
				end
			end
		end

		if signature.patterns then
			for _, entry in ipairs(signature.patterns) do
				local ok, matched = pcall(string.find, source, entry.pattern)
				if ok and matched then
					score += entry.weight
					evidence[#evidence + 1] = entry.label
				end
			end
		end

		if signature.custom then
			local bonus, label = signature.custom(source, metrics)
			if bonus > 0 then
				score += bonus
				if label then
					evidence[#evidence + 1] = label
				end
			end
		end

		if score > 0 then
			candidates[#candidates + 1] = {
				name = signature.name,
				score = score,
				evidence = evidence,
			}
		end
	end

	table.sort(candidates, function(a, b)
		if a.score == b.score then
			return a.name < b.name
		end
		return a.score > b.score
	end)

	local generic = genericEvidence(source, metrics)

	if #candidates == 0 then

		local looksObfuscated = #generic >= 2
		return {
			name = if looksObfuscated then "Unknown (obfuscated)" else "None detected",
			confidence = if looksObfuscated then "low" else "none",
			score = 0,
			evidence = generic,
			candidates = {},
			strategy = if looksObfuscated then "hybrid" else "plain",
			metrics = metrics,
		}
	end

	local best = candidates[1]
	local runnerUp = if #candidates > 1 then candidates[2].score else 0
	local margin = best.score - runnerUp

	local confidence: "high" | "medium" | "low"
	if best.score >= 50 and margin >= 20 then
		confidence = "high"
	elseif best.score >= 30 then
		confidence = "medium"
	else
		confidence = "low"
	end

	local strategy: any = "hybrid"
	local version: string? = nil
	for _, signature in ipairs(SIGNATURES) do
		if signature.name == best.name then
			strategy = signature.strategy
			if signature.version then

				local ok, captured = pcall(string.match, source, signature.version.pattern)
				if ok and type(captured) == "string" and captured ~= "" then
					version = captured
				end
			end
			break
		end
	end

	local combined = table.clone(best.evidence)
	for _, item in ipairs(generic) do
		combined[#combined + 1] = item
	end

	return {
		name = best.name,
		confidence = confidence,
		score = best.score,
		evidence = combined,
		candidates = candidates,
		strategy = strategy,
		version = version,
		metrics = metrics,
	}
end

return Detector
