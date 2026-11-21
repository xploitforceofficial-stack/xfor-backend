local Deobfuscation = {}

export type DecryptedString = {
    source: string,
    result: string,
    args: { any },
    timestamp: number,
}

local function isPrintable(s: string): boolean
    if #s < 4 then return false end
    local printable = 0
    for i = 1, #s do
        local b = string.byte(s, i)

        if b >= 32 and b <= 126 or b == 9 or b == 10 or b == 13 then
            printable += 1
        end
    end

    if printable / #s < 0.90 then return false end
    for i = 1, #s do
        if string.byte(s, i) == 0 then return false end
    end
    return true
end

local charHistory: { [string]: { string } } = setmetatable({}, { __mode = "k" })

function Deobfuscation.hookStringChar(
    realStringChar: (...any) -> string,
    trace: any,
    nest: number,
    onDecrypted: (decrypted: string, args: { any }) -> ()
): (...any) -> string
    return function(...: any): string
        local result = realStringChar(...)
        local argCount = select("#", ...)

        if argCount >= 2 and #result > 0 and isPrintable(result) then
            onDecrypted(result, { ... })
        end
        return result
    end
end

function Deobfuscation.hookBit32Bxor(
    realBxor: (...any) -> number,
    trace: any,
    nest: number,
    onXor: (a: number, b: number, result: number) -> ()
): (...any) -> number
    return function(...: any): number
        local result = realBxor(...)
        local a, b = select(1, ...)
        if type(a) == "number" and type(b) == "number" then
            onXor(a, b, result)
        end
        return result
    end
end

function Deobfuscation.hookTableConcat(
    realConcat: (...any) -> any,
    trace: any,
    nest: number,
    onAssembled: (result: string) -> ()
): (...any) -> any
    return function(...: any): any
        local result = realConcat(...)

        if type(result) == "string" and #result >= 200 and isPrintable(result) then
            onAssembled(result)
        end
        return result
    end
end

function Deobfuscation.hookStringLib(
    lib: { [string]: any },
    onAssembled: (result: string, via: string) -> ()
)
    for name, fn in pairs(lib) do
        if type(fn) == "function" then
            lib[name] = function(...: any): any
                local results = table.pack(fn(...))
                local first = results[1]
                if type(first) == "string" and #first >= 200 and isPrintable(first) then
                    onAssembled(first, name)
                end
                return table.unpack(results, 1, results.n)
            end
        end
    end
end

function Deobfuscation.extractStringTable(trace: any): { [string]: string }
    local table: { [string]: string } = {}
    for _, record in ipairs(trace.records) do
        if record.kind == "note" and type(record.expression) == "string" then
            local expr = record.expression
            local key, hex, value = expr:match('(%w+)%[(0x%x+)%]%s*=%s*"([^"]*)"')
            if key and hex and value then
                table[key .. "[" .. hex .. "]"] = value
            end
        end
    end
    return table
end

function Deobfuscation.extractStringTableFromSource(source: string): { [string]: string }
    local table: { [string]: string } = {}

    for hex, value in source:gmatch('%[(0x%x+)%]%s*=%s*"([^"]*)"') do
        table[hex] = value
    end

    for escaped in source:gmatch('"([^"\\]*\\x[%da-fA-F]+[^"\\]*)') do

        local decoded = escaped:gsub("\\x(%x%x)", function(hex)
            return string.char(tonumber(hex, 16) or 0)
        end)
        if #decoded >= 3 then
            table[decoded] = decoded
        end
    end
    return table
end

function Deobfuscation.eliminateDeadCode(source: string): string
    local lines = {}
    local inDeadBlock = false
    local deadIndent = 0
    local deadCount = 0

    for line in source:gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")

        if trimmed:find("didn't ran", 1, true) then

            local indent = #line:match("^(%s*)")
            if not inDeadBlock then
                inDeadBlock = true
                deadIndent = indent
            end
            deadCount += 1

        elseif trimmed:find("did ran", 1, true) then

            local cleanLine = line:gsub("%-%-.*did ran", "")
            if cleanLine:match("%S") then
                table.insert(lines, cleanLine)
            end
            inDeadBlock = false
        elseif inDeadBlock then

            local indent = #line:match("^(%s*)")
            if indent > deadIndent then

                deadCount += 1
            else

                inDeadBlock = false
                table.insert(lines, line)
            end
        else
            table.insert(lines, line)
        end
    end

    if deadCount > 0 then

        table.insert(lines, 1, "-- Dead code eliminated: " .. deadCount .. " dead branch lines removed")
    end

    return table.concat(lines, "\n")
end

local ANTI_TAMPER_PATTERNS = {

    {
        name = "debug.getinfo native check",
        detect = function(source: string)
            return source:find("debug.getinfo", 1, true) ~= nil
        end,
        bypass = function(source: string)
            return source
        end,
    },

    {
        name = "getfenv(0) check",
        detect = function(source: string)
            return source:find("getfenv(0)", 1, true) ~= nil
        end,
        bypass = function(source: string)
            return source
        end,
    },

    {
        name = "metatable check",
        detect = function(source: string)
            return source:find("getmetatable", 1, true) ~= nil
        end,
        bypass = function(source: string)
            return source
        end,
    },

    {
        name = "type() native check",
        detect = function(source: string)
            return source:find("type(print)", 1, true) ~= nil
                or source:find("type(", 1, true) ~= nil and source:find("== \"function\"", 1, true) ~= nil
        end,
        bypass = function(source: string)
            return source
        end,
    },

    {
        name = "hookfunction detection",
        detect = function(source: string)
            return source:find("hookfunction", 1, true) ~= nil
                or source:find("replaceclosure", 1, true) ~= nil
        end,
        bypass = function(source: string)
            return source
        end,
    },

    {
        name = "newproxy type check",
        detect = function(source: string)
            return source:find("newproxy", 1, true) ~= nil
        end,
        bypass = function(source: string)
            return source
        end,
    },

    {
        name = "setmetatable check",
        detect = function(source: string)
            return source:find("setmetatable", 1, true) ~= nil
                and source:find("getmetatable", 1, true) ~= nil
        end,
        bypass = function(source: string)
            return source
        end,
    },
}

function Deobfuscation.detectAntiTamper(source: string): { { name: string, detected: boolean } }
    local results = {}
    for _, pattern in ipairs(ANTI_TAMPER_PATTERNS) do
        table.insert(results, {
            name = pattern.name,
            detected = pattern.detect(source),
        })
    end
    return results
end

function Deobfuscation.bypassAntiTamper(source: string): string
    local result = source
    for _, pattern in ipairs(ANTI_TAMPER_PATTERNS) do
        if pattern.detect(result) then
            result = pattern.bypass(result)
        end
    end
    return result
end

function Deobfuscation.unrollStages(stages: { any }): string
    local parts = {}
    table.insert(parts, "-- Unrolled multi-stage loader (" .. #stages .. " stages)")
    table.insert(parts, "")

    for i, stage in ipairs(stages) do
        if type(stage) == "table" and stage.source and stage.source ~= "" then
            table.insert(parts, "-- Stage " .. i .. " (" .. (stage.origin or "unknown") .. ")")
            table.insert(parts, stage.source)
            table.insert(parts, "")
        elseif type(stage) == "table" and stage.data then
            table.insert(parts, "-- Stage " .. i .. " (binary data, " .. #stage.data .. " bytes)")
            table.insert(parts, "-- [binary data omitted for readability]")
            table.insert(parts, "")
        end
    end

    return table.concat(parts, "\n")
end

function Deobfuscation.shouldUnroll(stages: { any }): boolean
    local readableCount = 0
    for _, stage in ipairs(stages) do
        if type(stage) == "table" and stage.source and stage.source ~= "" then
            readableCount += 1
        end
    end
    return readableCount >= 2
end

return Deobfuscation
