local fs = require("@lune/fs")
local process = require("@lune/process")

fs.writeFile("tests/_at5_live_input.lua", fs.readFile("Samples/antitamperfound.lua"))

local ok = process.spawn("lune", { "run", "src/main.luau", "tests/_at5_live_input.lua" }, {
    cwd = ".",
    stdio = "pipe",
})
print("exit ok:", ok.ok)
local out = if ok.stdout then ok.stdout else ""
local lines = string.split(out, "\n")
print("output lines:", #lines)
local hits = 0
for _, line in ipairs(lines) do
    if string.find(line, "SKID", 1, true) or string.find(line, "GET TF OUT", 1, true) then
        hits += 1
        if hits <= 8 then print("HIT:", string.sub(line, 1, 160)) end
    end
end
print("signature hits:", hits)
fs.writeFile("tests/_at5_live_out.txt", out)
