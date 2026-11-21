local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run([[
local body = game:HttpGet("https://api.getpolsec.com/wl3?key=trial")
print("body type:", type(body))
print("len:", #body)
print("pcall JSONDecode on string:", pcall(function() return game:GetService("HttpService"):JSONDecode(body) end))
-- the killer pattern: method call on the RESPONSE OBJECT (not string)
local ok, err = pcall(function()
	local resp = body
	return resp:JSONDecode()
end)
print("str:JSONDecode:", ok, err)
-- via request global
local resp2 = request({Url = "https://api.getpolsec.com/wl3?key=trial", Method = "GET"})
print("request result:", type(resp2), resp2.Body and type(resp2.Body))
local ok2, err2 = pcall(function() return resp2.Body:JSONDecode() end)
print("body:JSONDecode:", ok2, err2)
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
