local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local cases = {
  "print(game.Workspace.CurrentCamera.Position)",
  "print(workspace.CurrentCamera.CFrame.Position)",
  "print(a.b.Position)",
  "local p = nil print(p.Position)",
  "local p = nil p:SetControlPoints({})",
}
for _, src in ipairs(cases) do
  print("IN :", src)
  local current = src
  for pass = 1, 3 do
    local ok, toks = pcall(Instrument.tokenize, current)
    if not ok then print(" token fail"); break end
    toks.src = current

    local w, e = SrcEdit.wrapSafeIndexing(current, Instrument.tokenize)
    print(" FULL:", w or ("ERR: " .. tostring(e)))
    break
  end
end
