local AntiNil = {}
AntiNil.__index = AntiNil

function AntiNil.new()
    return setmetatable({
        issues = {},
    }, AntiNil)
end

function AntiNil:log(line, kind, name, message)
    self.issues[#self.issues + 1] = {
        line = line,
        kind = kind,
        name = name,
        message = message
    }
end

return AntiNil
