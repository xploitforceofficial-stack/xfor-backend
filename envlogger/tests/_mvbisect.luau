local Sandbox = require("../src/core/sandbox")
local cases = {
	"print(1) local s = game:GetService('ReplicatedStorage') print('svc', s) print('p', s.Parent)",
	"print(1) print('sp', script.Parent)",
	"print(1) local w = Instance.new('WorldModel') print('w', w, w.Parent)",
	"print(1) local ws = game:GetService('Workspace') print('ws.Parent', ws.Parent)",
	"print(1) local g = getfenv() print('gscript', g.script) print('ggame', g.game)",
	"print(1) local pl = game:GetService('Players') print('lp', pl.LocalPlayer) print('lpp', pl.LocalPlayer.Parent)",
}
for i, c in ipairs(cases) do
	local ok, err = nil, nil
	local r = Sandbox.run(c, { timeout = 20, maxExplored = 0 })
	local out = {}
	for _, e in ipairs(r.outputs or {}) do out[#out+1] = e.text end
	print(i, "ok=" .. tostring(r.ok), "err=" .. tostring(r.err):sub(1, 80), "out=" .. table.concat(out, " | "):sub(1, 120))
end
