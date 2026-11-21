local rs = game:GetService("ReplicatedStorage")
local rem = Instance.new("RemoteEvent")
rem.Name = "StealData"
rem.Parent = rs
rem:FireServer("playerdata", 12345)
local key = "sk_live_51H7x9Q2mZ4KpL8vN3"
print("done")
