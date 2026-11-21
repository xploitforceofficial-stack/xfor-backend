local fs = require("@lune/fs")

local WORK = os.getenv("V14_WORK") or "tools/work"
local INPUT = os.getenv("V14_SAMPLE") or (WORK .. "/sample.lua")
local OUTBASE = os.getenv("V14_PROGOUT") or (WORK .. "/prog")
local LOG = os.getenv("V14_READLOG") or (WORK .. "/reads.log")
local MAX_READS = tonumber(os.getenv("V14_MAXREADS") or "") or 400000

local function note(msg)
    print("[capture] " .. msg)
end

if loadstring == nil then
    loadstring = load
end
if unpack == nil then
    unpack = table.unpack
end

local logLines = {}
local readCount = 0
local batch = 0
local wrapped = {}
local targetBuf = nil
local targetId = nil

local function flush()
    if #logLines == 0 then
        return
    end
    batch += 1
    pcall(fs.writeFile, string.format("%s.%03d", LOG, batch),
        table.concat(logLines, "\n") .. "\n")
    logLines = {}
end

local function finalise()
    flush()
    local parts = {}
    local okList = pcall(function()
        for _, name in ipairs(fs.readDir(string.match(LOG, "^(.*)[/\\]") or ".")) do
            local n = tonumber(string.match(name, "^reads%.log%.(%d+)$"))
            if n then
                parts[n] = fs.readFile(LOG .. "." .. string.format("%03d", n))
            end
        end
    end)
    if okList then
        local out = {}
        for i = 1, #parts do
            out[i] = parts[i]
        end
        pcall(fs.writeFile, LOG, table.concat(out))
    end
end

local function log(line)
    readCount += 1
    if readCount > MAX_READS then
        if readCount == MAX_READS + 1 then
            logLines[#logLines + 1] = "TRUNCATED at " .. MAX_READS
            flush()
        end
        return
    end
    logLines[#logLines + 1] = line
    if #logLines >= 2000 then
        flush()
    end
end

local realBuffer = buffer

local lastName = nil
local debugInfo = debug and debug.info

local function caller()
    if debugInfo == nil then
        return "?"
    end
    for lvl = 3, 8 do
        local ok, name = pcall(debugInfo, lvl, "n")
        if not ok or name == nil then
            break
        end
        if name ~= "" then
            local okL, line = pcall(debugInfo, lvl, "l")
            if okL and line then
                return name .. ":" .. tostring(line)
            end
            return name
        end
    end
    return "?"
end

local function wrap(name, width, fmt)
    local real = realBuffer[name]
    if real == nil then
        return
    end
    wrapped[name] = function(buf, off, ...)
        if targetId ~= nil and tostring(buf) == targetId then
            local v = real(buf, off, ...)
            local extra = ""
            if select("#", ...) > 1 then
                extra = " ..." .. tostring((select(2, ...)))
            end
            local who = caller()
            if who ~= lastName then
                lastName = who
                log("CALLER " .. who)
            end
            log(string.format("%s off=%d%s = %s", name, off, extra, tostring(v)))
            return v
        end
        return real(buf, off, ...)
    end
end

wrap("readu8")
wrap("reads8")
wrap("readu16")
wrap("readi16")
wrap("readu32")
wrap("readi32")
wrap("readf32")
wrap("readf64")
wrap("readstring")

local proxy = setmetatable({}, {
    __index = function(_, k)
        if wrapped[k] then
            return wrapped[k]
        end
        return realBuffer[k]
    end,
})

local proxyOk = pcall(function()
    buffer = proxy
end)
note("buffer proxy installed=" .. tostring(proxyOk))

local realLoad = loadstring
local saved = 0

loadstring = function(text, chunkname, mode, env)

    if type(text) ~= "string" then
        error("bad argument #1 to 'load' (string expected, got " .. type(text) .. ")", 2)
    end
    local fn, err = realLoad(text, chunkname, mode, env)
    if not fn then
        return fn, err
    end
    return function(...)
        local n = select("#", ...)
        for i = 1, n do
            local v = select(i, ...)
            local t = type(v)
            if t == "buffer" or t == "string" then
                saved += 1
                local path = string.format("%s_%d.%s", OUTBASE, saved, t == "buffer" and "bin" or "txt")
                local ok, body = pcall(function()
                    if t == "buffer" then
                        return realBuffer.tostring(v)
                    end
                    return v
                end)
                if ok and type(body) == "string" then
                    pcall(fs.writeFile, path, body)
                    note(string.format("arg %d (%s, %d bytes) -> %s", i, t, #body, path))
                    if t == "buffer" and targetBuf == nil then
                        targetBuf = v
                        targetId = tostring(v)
                        log("# target " .. targetId .. " len=" .. tostring(realBuffer.len(v)))
                        note("tracking reads on " .. targetId)
                    end
                end
            else
                note(string.format("arg %d type=%s", i, t))
            end
        end

        local packed = table.pack(pcall(fn, ...))
        finalise()
        note("stage finished ok=" .. tostring(packed[1]) .. " err=" .. tostring(packed[2])
            .. " reads=" .. tostring(readCount))
        if not packed[1] then
            error(packed[2], 0)
        end
        return table.unpack(packed, 2, packed.n)
    end
end

local src = fs.readFile(INPUT)
note("loading sample (" .. #src .. " bytes)")
local chunk, err = realLoad(src, "=sample")
if not chunk then
    note("load failed: " .. tostring(err))
    error("load failed: " .. tostring(err))
end

local ok, runErr = pcall(chunk)
finalise()
note("sample finished ok=" .. tostring(ok) .. " err=" .. tostring(runErr))
note("total reads on target=" .. tostring(readCount))
