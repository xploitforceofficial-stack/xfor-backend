local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local src = "local p = nil p:SetControlPoints({}) print(p.Position) print(game.Workspace.CurrentCamera.Position)"
local w, e = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
print("OUT:", w or ("ERR: " .. tostring(e)))
local safeCount = 0
if w then
  for _ in string.gmatch(w, "__FUHD_SAFE__%(%)") do safeCount += 1 end
  local safeIdx = 0
  for _ in string.gmatch(w, "__FUHD_SAFE_INDEX__") do safeIdx += 1 end
  print("SAFE calls:", safeCount, "SAFE_INDEX:", safeIdx)
end
