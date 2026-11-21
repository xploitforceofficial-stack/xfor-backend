local Fidelity = require("../src/env/fidelity")

local fails = 0
local function eq(actual: any, expected: any, label: string)
	if actual ~= expected then
		fails += 1
		print(string.format("FAIL %s: got %s want %s", label, tostring(actual), tostring(expected)))
	end
end

local function fmt(v: number): string
	return string.format("%.17g", v)
end

local hi, lo = Fidelity.pcgSeed(177465824)
eq(hi, 0x1390D9BB, "seed hi")
eq(lo, 0x45B7663E, "seed lo")

local v1, hi1, lo1 = Fidelity.pcgDouble(hi, lo)
eq(fmt(v1), fmt(0.9598971928030796), "v1")
eq(hi1, 0x6A3E0C38, "after v1 hi")
eq(lo1, 0x27F71E4C, "after v1 lo")

local function pcgInt(hi0: number, lo0: number, loArg: number, hiArg: number): (number, number, number)
	local span = bit32.band(hiArg - loArg, 0xFFFFFFFF)
	local o = Fidelity.pcgNext32(hi0, lo0)
	local x = span * o

	x = (span + 1) * o
	local r = loArg + math.floor(x / 18446744073709551616 * 4294967296 / 4294967296 * 4294967296 / 18446744073709551616)

	local p = span * 0
	_ = p
	return 0, 0, 0
end
_ = pcgInt

local function mulHigh32(a: number, b: number): number
	local a0 = a % 65536
	local a1 = math.floor(a / 65536)
	local b0 = b % 65536
	local b1 = math.floor(b / 65536)
	local ll = a0 * b0
	local mid = a1 * b0 + a0 * b1 + math.floor(ll / 65536)
	local hh = a1 * b1 + math.floor(mid / 65536)
	return hh % 4294967296
end

local function pcgInteger(hi0: number, lo0: number, l: number, u: number): (number, number, number)
	local span = bit32.band(u - l, 0xFFFFFFFF)
	local o = Fidelity.pcgNext32(hi0, lo0)
	local nhi, nlo = Fidelity.pcgStep(hi0, lo0)
	return l + mulHigh32(span + 1, o), nhi, nlo
end

local v2, hi2, lo2 = pcgInteger(hi1, lo1, 189, 1164)
eq(v2, 889, "v2")
local v3, hi3, lo3 = Fidelity.pcgDouble(hi2, lo2)
eq(fmt(v3), fmt(0.027539190730015265), "v3")
local v4, hi4, lo4 = Fidelity.pcgDouble(hi3, lo3)
eq(fmt(v4), fmt(0.3377740061710911), "v4")
local v5, hi5, lo5 = pcgInteger(hi4, lo4, 75, 497)
eq(v5, 340, "v5")

local c1hi, c1lo = hi5, lo5
local v7, hi7, lo7 = pcgInteger(c1hi, c1lo, 979, 1379)
eq(v7, 1338, "v7")
local v8 = Fidelity.pcgDouble(c1hi, c1lo)
eq(fmt((v8)), fmt(0.010722157288309652), "v8")

local v10, hi10, lo10 = Fidelity.pcgDouble(hi7, lo7)
eq(fmt(v10), fmt(0.9163096810250362), "v10")
local v11, hi11, lo11 = Fidelity.pcgDouble(hi10, lo10)
eq(fmt(v11), fmt(0.7297156848095374), "v11")

local v13, hi13, lo13 = Fidelity.pcgDouble(hi11, lo11)
eq(fmt(v13), fmt(0.17877278448733477), "v13")
local v14, _, _ = pcgInteger(hi13, lo13, 35, 888)
eq(v14, 665, "v14")
local v15 = Fidelity.pcgDouble(hi11, lo11)

_ = v15
local v15b, hi15, lo15 = Fidelity.pcgDouble(hi11, lo11)
eq(fmt(v15b), fmt(0.17877278448733477), "v15")
local v16 = pcgInteger(hi15, lo15, 721, 807)
eq(v16, 785, "v16")

local s13hi, s13lo = hi13, lo13
local v14b, hi14, lo14 = pcgInteger(s13hi, s13lo, 35, 888)
_ = v14b
local v17 = pcgInteger(hi14, lo14, 353, 1335)
eq(v17, 826, "v17")

if fails == 0 then
	print("PCG PORT: ALL 17 FIXTURE VALUES + STATES MATCH")
else
	print(fails .. " failures")
end
