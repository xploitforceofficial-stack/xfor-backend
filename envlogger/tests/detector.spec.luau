local fs = require("@lune/fs")
local process = require("@lune/process")
local Detector = require("../src/analysis/detector")

local passed, failed = 0, 0
local failures: { string } = {}

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		failures[#failures + 1] = name .. (if detail then "  -> " .. detail else "")
	end
end

local samples = {
	{ path = "Samples/moonsecv3sample.lua", expect = "MoonSec V3", strategy = "vm" },
	{ path = "Samples/prometheusORwearedevs.lua", expect = "WeAreDevs", strategy = "loadstring" },
	{ path = "Samples/prometheusORwearedevsLUAU.lua", expect = nil, strategy = nil },
}

for _, sample in ipairs(samples) do
	local ok, source = pcall(fs.readFile, sample.path)
	if not ok then
		check("read " .. sample.path, false, "missing file")
	else
		local result = Detector.detect(source)
		print(string.format(
			"%-42s -> %-22s %s (score %d)",
			sample.path,
			result.name,
			result.confidence,
			result.score
		))
		print("      evidence: " .. table.concat(result.evidence, "; "))
		print(string.format(
			"      %d bytes, %d lines, longest %d, printable %.0f%%",
			result.metrics.bytes,
			result.metrics.lines,
			result.metrics.longestLine,
			result.metrics.printableRatio * 100
		))

		if sample.expect then
			check("detect " .. sample.path, result.name == sample.expect,
				"got " .. result.name)
			check("strategy " .. sample.path, result.strategy == sample.strategy,
				"got " .. result.strategy)
			check("confidence " .. sample.path,
				result.confidence == "high" or result.confidence == "medium",
				"got " .. result.confidence)
		else

			check("flags " .. sample.path .. " as obfuscated",
				result.confidence ~= "none", "got " .. result.confidence)
		end
	end
end

do
	local plain = [[
		local Players = game:GetService("Players")
		local player = Players.LocalPlayer

		local function greet(name)
			print("hello " .. name)
		end

		greet(player.Name)
	]]
	local result = Detector.detect(plain)
	check("plain script not flagged", result.confidence == "none",
		result.name .. "/" .. result.confidence)
	check("plain strategy", result.strategy == "plain", result.strategy)
end

do

	local lines = {}
	for i = 1, 500 do
		lines[#lines + 1] = string.format("local variable%d = %d + %d", i, i, i * 2)
	end
	local result = Detector.detect(table.concat(lines, "\n"))
	check("long plain script not flagged", result.confidence == "none",
		result.name .. "/" .. result.confidence)
end

do
	local empty = Detector.detect("")
	check("empty input safe", empty.confidence == "none", empty.name)
	check("empty metrics", empty.metrics.bytes == 0)
end

do
	local luraph = Detector.detect([[

		LPH_JIT_MAX(function() end)
		local x = "(does your environment support load/loadstring?)"
	]])
	check("luraph detected", luraph.name == "Luraph", luraph.name)
	check("luraph high confidence", luraph.confidence == "high", luraph.confidence)
	check("luraph strategy vm", luraph.strategy == "vm")

	local ironbrew = Detector.detect([[ -- IronBrew2 obfuscated payload
		local a=string.byte;local b=string.char
	]])
	check("ironbrew detected", ironbrew.name == "IronBrew2", ironbrew.name)

	local prometheus = Detector.detect([[

		local x = (-290332+290333)
	]])
	check("prometheus detected", prometheus.name == "Prometheus", prometheus.name)
	check("prometheus strategy loadstring", prometheus.strategy == "loadstring")

	local luarmor = Detector.detect([[ -- luarmor.net protected
		LRM_Loader()
	]])
	check("luarmor detected", luarmor.name == "Luarmor", luarmor.name)
end

do

	local upper = Detector.detect("-- MOONSEC V3 PROTECTED\nThis file was protected with MoonSec V3")
	check("case-insensitive match", upper.name == "MoonSec V3", upper.name)
end

do

	local mixed = Detector.detect([[

	]])
	check("mixed picks strongest", mixed.name == "Luraph", mixed.name)
	check("mixed lists candidates", #mixed.candidates >= 2, tostring(#mixed.candidates))
end

do
	local luraph15 = Detector.detect([[

		return(function() local R,s=string.byte,5 end)
	]])
	check("luraph v15 version", luraph15.name == "Luraph" and luraph15.version == "15.0",
		luraph15.name .. "/" .. tostring(luraph15.version))

	local luraph1 = Detector.detect("-- This file was generated using Luraph Obfuscator v1 by memcorrupt.")
	check("luraph v1 version", luraph1.version == "1", tostring(luraph1.version))

	local psu = Detector.detect([[local R="This file was obfuscated using PSU Obfuscator 4.5.A | https://www.psu.dev/"]])
	check("psu version", psu.name == "PSU / Xen" and psu.version == "4.5.A",
		psu.name .. "/" .. tostring(psu.version))

	local moonsec = Detector.detect("([[This file was protected with MoonSec V3]]):gsub('+', function() end)")
	check("moonsec v3 version", moonsec.name == "MoonSec V3" and moonsec.version == "3",
		moonsec.name .. "/" .. tostring(moonsec.version))

	local f77 = Detector.detect("do local a=[[77fuscator 0.6.5 discord.gg/x]];return(function(a) end)end")
	check("77fuscator version", f77.name == "77fuscator" and f77.version == "0.6.5",
		f77.name .. "/" .. tostring(f77.version))

	local hercules = Detector.detect("--[Obfuscated by Hercules v1.6.2 | hercules-obfuscator.xyz/discord]")
	check("hercules version", hercules.name == "Hercules" and hercules.version == "1.6.2",
		hercules.name .. "/" .. tostring(hercules.version))

	local xen = Detector.detect("--[[ Synapse Xen v1.1.2 by Synapse GP ]] local x = 1")
	check("synapse xen version", xen.name == "Synapse Xen" and xen.version == "1.1.2",
		xen.name .. "/" .. tostring(xen.version))

	local boronide = Detector.detect("--[[ herrtt's obfuscator, v0.2.4 --]] local a,b,c=nil,nil,nil([[herrtts obf, discord.gg/BZEjFbeUvk]])")
	check("boronide version", boronide.name == "Boronide" and boronide.version == "0.2.4",
		boronide.name .. "/" .. tostring(boronide.version))

	local plain = Detector.detect("local x = 1 print(x)")
	check("no version on plain", plain.version == nil, tostring(plain.version))
end

print(string.format("\ndetector: %d passed, %d failed", passed, failed))
if failed > 0 then
	for _, line in ipairs(failures) do
		print("  FAIL  " .. line)
	end
	process.exit(1)
end
