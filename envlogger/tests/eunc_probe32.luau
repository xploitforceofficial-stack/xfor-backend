local Services = require("../src/env/services")
local m = Services.members("EncodingService")
print("members:", m ~= nil)
if m then
	for k in pairs(m.methods or {}) do print("method:", k) end
	for k in pairs(m.props or {}) do print("prop:", k) end
end
