local process = require("@lune/process")
print("spawn:", type(process.spawn))
print("exec:", type(process.exec))
print(os.clock())
