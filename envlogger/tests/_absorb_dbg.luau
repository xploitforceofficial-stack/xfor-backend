local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")

local src = "print(workspace.CurrentCamera.CFrame.Position)"
print("ORIG:", src)

local function showPass(label, s)
  print(label, s)
end

local src1 = "print(__FUHD_SAFE_INDEX__(workspace, \"CurrentCamera\").CFrame.Position)"
local w1, e1 = SrcEdit.wrapSafeIndexing(src1, Instrument.tokenize)
print("from intermediate:", w1 or e1)

local src2 = "print(__FUHD_SAFE_INDEX__(workspace, \"CurrentCamera\").Position)"
local w2, e2 = SrcEdit.wrapSafeIndexing(src2, Instrument.tokenize)
print("from intermediate2:", w2 or e2)

local src3 = "print(__FUHD_SAFE_INDEX__(game.Workspace, \"CurrentCamera\").Position)"
local w3, e3 = SrcEdit.wrapSafeIndexing(src3, Instrument.tokenize)
print("from intermediate3:", w3 or e3)
