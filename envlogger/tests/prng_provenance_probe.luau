local fs = require("@lune/fs")
local Report = require("../src/analysis/report")
local Sandbox = require("../src/core/sandbox")

local src = [[
local r = Random.new(177465824)
if r:NextNumber() ~= 0.9598971928030796 then
    print("tampered")
else
    print("clean")
end
local n = r:NextInteger(1, 10)
if n == 5 then
    print("five")
end
]]

local result = Sandbox.run(src, { timeout = 60, maxExplored = 0 })
print("ok:", result.ok, "err:", tostring(result.err):sub(1, 120))

local report = Report.render({
	trace = result.trace,
	stages = result.stages,
	outputs = result.outputs,
	ok = result.ok,
	err = result.err,
	exhausted = result.exhausted,
	exhaustedReason = result.exhaustedReason,
	explored = result.explored,
})
local text = typeof(report) == "string" and report or tostring(report)

local disclosed = string.find(text, "decided by the sandbox", 1, true) ~= nil
print("discloses sandbox-decided:", disclosed)

local hits = 0
for line in string.gmatch(text, "[^\n]+") do
    if string.find(line, "guessed:", 1, true) then
        hits += 1
        print("  " .. line:sub(1, 120))
    end
end
print("guessed-op lines:", hits)
