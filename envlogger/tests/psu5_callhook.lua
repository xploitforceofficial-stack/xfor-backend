local env = {}
for k, v in PSU_ENVMAP_JSON:gmatch('"([^"]+)":%s*"?([^,}%n]+)"?') do
    local nv = tonumber(v)
    if k:match('^%d+$') then env[tonumber(k)] = nv
    else env[k] = nv or v end
end

local src = PSU_BODY
local marker = 'return A(I(),{},v())(...);end)'
local mi = src:find(marker, 1, true)
if not mi then return 'TAIL MARKER NOT FOUND' end
src = src:sub(1, mi + #marker - 2)

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

local chunk, lerr = load(lineated, 'b', 't', _G)
if not chunk then return 'LINEATE LOADFAIL ' .. tostring(lerr) end

local bootstrap = chunk()

local log = {}
local depth = 0
local MAXLOG = 200
debug.sethook(function(ev)
    local info = debug.getinfo(2, 'nSl')
    if not info then return end
    if ev == 'call' then
        depth = depth + 1
        if #log < MAXLOG then
            log[#log+1] = string.rep(' ', depth) .. 'CALL ' ..
                (info.name or '?') .. ' @' .. tostring(info.currentline) ..
                ' ' .. tostring(info.short_src):sub(-14)
        end
    elseif ev == 'return' then
        if depth > 0 then depth = depth - 1 end
    end
end, 'cr')

local function handler(err)
    debug.sethook()
    return tostring(err) .. '\n== last calls ==\n' .. table.concat(log, '\n')
end

local ok, ret = xpcall(bootstrap, handler, env)
debug.sethook()
return table.concat({"after:", tostring(ok), tostring(ret):sub(1, 2500)}, " | ")
