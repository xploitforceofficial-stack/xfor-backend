local env = {}
for k, v in PSU_ENVMAP_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
    local nv = tonumber(v)
    if k:match('^%d+$') then env[tonumber(k)] = nv
    else env[k] = nv or v end
end
env['FJ3bzQ5i0j'] = 20
env['QCl5H']      = setmetatable
env['udTlwPHfj']  = tostring

local bodyenv = setmetatable({ K = math.ldexp, D = math.floor }, { __index = _G })

local src = PSU_BODY
local marker = 'return A(I(),{},v())(...);end)'
local mi = src:find(marker, 1, true)
src = src:sub(1, mi + #marker - 2)

src = src:gsub('return A%(I%,%{%},v%(%)%)%(%.%.%.%);',
               'local _r = {A(I(),{},v())}; return unpack(_r);')
src = src .. '\nreturn f\n'

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
PSU_LINEATED = lineated

local chunk, lerr = load(lineated, 'PSU5LINEATED', 't', bodyenv)
if not chunk then return 'LOADFAIL ' .. tostring(lerr) end
local bootstrap = chunk()

local frames = {}
local function handler(err)
    for lvl = 1, 12 do
        local info = debug.getinfo(lvl, 'nSl')
        if not info then break end
        frames[#frames+1] = lvl .. ': ' .. (info.name or '?') .. ' line=' ..
            tostring(info.currentline) .. ' src=' .. tostring(info.short_src):sub(-14)
    end
    return tostring(err)
end

local ok, ret = xpcall(bootstrap, handler, env)
if not ok then
    return 'ERR | ' .. tostring(ret) .. ' || frames: ' .. table.concat(frames, ' || '):sub(1, 900)
end
return 'OK | ' .. type(ret)
