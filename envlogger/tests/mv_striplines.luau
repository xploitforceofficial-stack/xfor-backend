local Sanitize = require("../src/core/sanitize")

local msg = "C:\\Users\\Sandr\\OneDrive\\Desktop\\OmniDBF\\envlogger\\src\\env\\control:127: [string \"\"]: attempt to index function with 'FindFirstChild'"
print("internalLocation ->", Sanitize.internalLocation(msg))
print("message ->", Sanitize.message(msg))
