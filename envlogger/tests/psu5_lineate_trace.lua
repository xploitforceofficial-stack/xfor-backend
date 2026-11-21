local env = {}
for k, v in PSU_ENVMAP_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
    local nv = tonumber(v)
    if k:match('^%d+$') then env[tonumber(k)] = nv
    else env[k] = nv or v end
end

local src = PSU_BODY
local out = {}
local i, n = 1, #src
local in_str = nil
while i <= n do
    local c = src:sub(i, i)
    out[#out+1] = c
    if in_str then
        if c == '\\' then
            out[#out+1] = src:sub(i+1, i+1)
            i = i + 2
        elseif c == in_str then
            in_str = nil
            i = i + 1
        else
            i = i + 1
        end
    else
        if c == '"' or c == "'" then
            in_str = c
            i = i + 1
        elseif c == ';' then
            out[#out+1] = '\n'
            i = i + 1
        else
            i = i + 1
        end
    end
end
local lineated = table.concat(out)
local chunk, lerr = load(lineated, 'b', 't', _G)
if not chunk then return 'LINEATE LOADFAIL ' .. tostring(lerr) end

local bootstrap = chunk()
local function handler(err)
    return debug.traceback(tostring(err), 2)
end
local ok, ret = xpcall(bootstrap, handler, env)
return table.concat({"after:", tostring(ok), tostring(ret):sub(1, 1200)}, " | ")
