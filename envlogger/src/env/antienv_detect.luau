local AntiEnvDetect = {}

type PatternMatch = {
    id: string,
    name: string,
    severity: "info" | "warn" | "critical",
    family: string,
    description: string,
    source_line: string?,
}

local patterns: { { match: (src: string, records: { any }?) -> PatternMatch? } } = {}

local function addPattern(fn: (src: string, records: { any }?) -> PatternMatch?)
    patterns[#patterns + 1] = { match = fn }
end

addPattern(function(src: string): PatternMatch?
    if string.find(src, "_VERSION", 1, true) ~= nil
        and (string.find(src, "Luau", 1, true) ~= nil or string.find(src, "Lua 5", 1, true) ~= nil)
    then
        return {
            id = "version_check",
            name = "_VERSION check",
            severity = "info",
            family = "generic",
            description = "Script checks _VERSION (Lua/Luau runtime fingerprint)",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    local count = 0
    local pos = 1
    while true do
        local s = string.find(src, "IsStudio", pos, true)
        if s == nil then break end
        count += 1
        pos = s + 1
    end
    if count >= 3 then
        return {
            id = "isstudio_loop",
            name = "IsStudio repeated check",
            severity = "critical",
            family = "generic",
            description = string.format(
                "IsStudio called %d times - likely an anti-tamper loop verifying false negatives",
                count
            ),
        }
    elseif count >= 1 then
        return {
            id = "isstudio_check",
            name = "IsStudio check",
            severity = "warn",
            family = "generic",
            description = "Script checks RunService:IsStudio() to detect Studio environment",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "@lune/", 1, true) ~= nil
        or string.find(src, "require.*lune", 1) ~= nil
        or string.find(src, "lune", 1, true) ~= nil and string.find(src, "detect", 1, true) ~= nil
    then
        return {
            id = "lune_detect",
            name = "Lune runtime detection",
            severity = "critical",
            family = "generic",
            description = "Script detects Lune runtime to identify non-Roblox environments",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "CorePackages", 1, true) ~= nil then
        return {
            id = "corepackages_check",
            name = "CorePackages service check",
            severity = "warn",
            family = "OmniDBF",
            description = "Script checks CorePackages service - only available in real Roblox",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "GetPlayers", 1, true) ~= nil
        and (string.find(src, ":IsA", 1, true) ~= nil or string.find(src, "ClassName", 1, true) ~= nil)
    then
        return {
            id = "player_validate",
            name = "Player instance validation",
            severity = "critical",
            family = "OmniDBF",
            description = "Script validates that GetPlayers() returns actual Player instances",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "VoiceChatService", 1, true) ~= nil
        and (string.find(src, "joinVoice", 1, true) ~= nil
            or string.find(src, "rejoinVoice", 1, true) ~= nil
            or string.find(src, "leaveVoice", 1, true) ~= nil)
    then
        return {
            id = "vc_methods",
            name = "VoiceChatService method checks",
            severity = "critical",
            family = "OmniDBF",
            description = "Script checks VoiceChatService method types - tests executor quality",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "SoundService", 1, true) ~= nil
        and (string.find(src, "GetAudioInstances", 1, true) ~= nil
            or string.find(src, "GetInputDevices", 1, true) ~= nil
            or string.find(src, "GetOutputDevices", 1, true) ~= nil)
    then
        return {
            id = "ss_methods",
            name = "SoundService method checks",
            severity = "critical",
            family = "OmniDBF",
            description = "Script checks SoundService API methods - verifies real Roblox environment",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "CreateEditableMesh", 1, true) ~= nil
        and string.find(src, "AddVertex", 1, true) ~= nil
        and string.find(src, "GetPosition", 1, true) ~= nil
    then
        return {
            id = "mesh_roundtrip",
            name = "AssetService mesh round-trip",
            severity = "critical",
            family = "OmniDBF",
            description = "Script creates editable mesh, adds vertices, verifies positions round-trip correctly",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "SharedTable", 1, true) ~= nil
        and (string.find(src, "cloneAndFreeze", 1, true) ~= nil
            or string.find(src, "isFrozen", 1, true) ~= nil)
    then
        return {
            id = "sharedtable_check",
            name = "SharedTable behavior check",
            severity = "critical",
            family = "generic",
            description = "Script tests SharedTable clone/freeze semantics - deep engine behavior test",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "identifyexecutor", 1, true) ~= nil
        or string.find(src, "getexecutorname", 1, true) ~= nil
    then
        return {
            id = "executor_check",
            name = "Executor identity check",
            severity = "warn",
            family = "generic",
            description = "Script checks executor identity (Synapse, KRNL, Fluxus, etc.)",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "gethwid", 1, true) ~= nil
        or string.find(src, "getHWID", 1, true) ~= nil
        or string.find(src, "HWID", 1, true) ~= nil
        or string.find(src, "HardwareId", 1, true) ~= nil
    then
        return {
            id = "hwid_check",
            name = "HWID fingerprinting",
            severity = "warn",
            family = "generic",
            description = "Script accesses hardware ID - used for executor-specific behavior",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "getrawmetatable", 1, true) ~= nil
        or string.find(src, "getmetatable", 1, true) ~= nil and string.find(src, "raw", 1, true) ~= nil
    then
        return {
            id = "metatable_probe",
            name = "Raw metatable access",
            severity = "warn",
            family = "generic",
            description = "Script probes raw metatables - tests executor capabilities",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "hookfunction", 1, true) ~= nil
        or string.find(src, "replaceclosure", 1, true) ~= nil
        or string.find(src, "hookmetamethod", 1, true) ~= nil
    then
        return {
            id = "hook_check",
            name = "Function hooking API",
            severity = "warn",
            family = "generic",
            description = "Script tests function hooking capabilities - advanced executor feature",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "iscclosure", 1, true) ~= nil
        or string.find(src, "islclosure", 1, true) ~= nil
    then
        return {
            id = "closure_type_check",
            name = "Closure type detection",
            severity = "warn",
            family = "generic",
            description = "Script checks C vs Lua closure types - tests executor fidelity",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "getconnections", 1, true) ~= nil
        or string.find(src, "firesignal", 1, true) ~= nil
    then
        return {
            id = "signal_probe",
            name = "Signal connection probing",
            severity = "warn",
            family = "generic",
            description = "Script probes signal connections - tests executor deep API",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "Drawing.new", 1, true) ~= nil
        or string.find(src, "Drawing.", 1, true) ~= nil and string.find(src, "Line", 1, true) ~= nil
    then
        return {
            id = "drawing_check",
            name = "Drawing library probe",
            severity = "info",
            family = "generic",
            description = "Script uses Drawing library - executor-specific UI overlay API",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "debug.info", 1, true) ~= nil
        or string.find(src, "debug.getinfo", 1, true) ~= nil
        or string.find(src, "debug.traceback", 1, true) ~= nil
    then
        local isAntiEnv = string.find(src, "error", 1, true) ~= nil
            and string.find(src, "pcall", 1, true) ~= nil
        if isAntiEnv then
            return {
                id = "anti_debug",
                name = "Anti-debug instrumentation",
                severity = "warn",
                family = "generic",
                description = "Script uses debug library in error-checking context - anti-tamper probe",
            }
        end
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "getthreadidentity", 1, true) ~= nil
        or string.find(src, "getidentity", 1, true) ~= nil
        or string.find(src, "getthreadcontext", 1, true) ~= nil
    then
        return {
            id = "identity_check",
            name = "Thread identity check",
            severity = "info",
            family = "generic",
            description = "Script checks thread identity level - tests executor context",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "detected by", 1, true) ~= nil
        or string.find(src, "BALL knowledge", 1, true) ~= nil
    then
        return {
            id = "detection_msg",
            name = "Anti-env detection message",
            severity = "critical",
            family = "OmniDBF",
            description = "Script contains anti-env detection output message - checks FAILED",
        }
    end
    return nil
end)

addPattern(function(src: string): PatternMatch?
    if string.find(src, "while true do", 1, true) ~= nil
        and string.find(src, "detected", 1, true) ~= nil
    then
        return {
            id = "freeze_loop",
            name = "Detection freeze loop",
            severity = "critical",
            family = "OmniDBF",
            description = "Script enters infinite loop after detection - anti-tamper freeze",
        }
    end
    return nil
end)

function AntiEnvDetect.analyze(source: string, records: { any }?): { PatternMatch }
    local matches: { PatternMatch } = {}
    local seen: { [string]: boolean } = {}

    for _, entry in ipairs(patterns) do
        local result = entry.match(source, records)
        if result and not seen[result.id] then
            seen[result.id] = true
            matches[#matches + 1] = result
        end
    end

    local severityOrder = { critical = 3, warn = 2, info = 1 }
    table.sort(matches, function(a, b)
        return (severityOrder[a.severity] or 0) > (severityOrder[b.severity] or 0)
    end)

    return matches
end

return AntiEnvDetect
