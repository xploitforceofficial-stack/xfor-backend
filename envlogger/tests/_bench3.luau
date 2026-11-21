local Sandbox = require("../src/core/sandbox")
local cases = {
  { name = "table-rw", src = [[local t = {} local acc = 0 for i = 1, 300000 do t[i] = i acc = acc + t[i] end return acc]] },
  { name = "dispatch", src = [[local x = 0 local n = 0 for i = 1, 300000 do if x == 0 then x = 1 elseif x == 1 then x = 2 elseif x == 2 then x = 3 else x = 0 end n = n + x end return n]] },
  { name = "string-build", src = [[local parts = {} for i = 1, 20000 do parts[i] = string.char(97 + (i % 26)) end return #table.concat(parts)]] },
  { name = "closures", src = [[local s = 0 for i = 1, 100000 do local f = function(a) return a + 1 end s = s + f(i) end return s]] },
}
for _, mode in ipairs({ "default", "raw" }) do
  for _, c in ipairs(cases) do
    local opts: any = { timeout = 60 }
    if mode == "raw" then opts.noInstrument = true end
    local t0 = os.clock()
    local ok = pcall(function() return Sandbox.run(c.src, opts) end)
    print(string.format("%-8s %-13s wall=%.2fs", mode, c.name, os.clock() - t0))
  end
end
