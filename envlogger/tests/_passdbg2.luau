local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")

local src = "print(workspace.CurrentCamera.CFrame.Position)"
print("ORIG:", src)
local current = src
for pass = 1, 4 do
  local ok, toks = pcall(Instrument.tokenize, current)
  if not ok then print("token fail", toks); break end
  toks.src = current

  print("pass"..pass.." in:", current)
  break
end

local function onePass(src)
  local w, e = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
  return w or ("ERR:"..tostring(e))
end
print("all-pass:", onePass(src))

for _, s in ipairs({
  "print(workspace.CurrentCamera.Position)",
  "print(workspace.CurrentCamera.CFrame.Position)",
  "local x = workspace.CurrentCamera x.Position",
  "print(game.Workspace.CurrentCamera.Position)",
  "print(a.b.Position)",
}) do
  print("IN:", s)
  print("OUT:", onePass(s))
end
