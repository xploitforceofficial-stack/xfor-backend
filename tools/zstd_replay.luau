local fs = require("@lune/fs")
local process = require("@lune/process")

local Zstd = require("../envlogger/src/env/zstd")

local framePath = process.args[1]
if not framePath then
    print("usage: lune run tools/zstd_replay.luau <frame.bin> [expected.bin]")
    return
end
local frame = fs.readFile(framePath)
print(("frame %s: %d bytes, isFrame=%s"):format(
    framePath, #frame, tostring(Zstd.isFrame(frame))))

local expected = nil
local expPath = process.args[2]
if expPath then
    local ok, data = pcall(fs.readFile, expPath)
    if ok then
        expected = data
    end
end

local ok, out, err = pcall(Zstd.decompress, frame)
if not ok then
    print("DECODE RAISED:", tostring(out))
    return
end
if type(out) ~= "string" then
    print("DECODE FAILED:", tostring(err or out))
    return
end
print(("decoded %d bytes"):format(#out))
if expected then
    if out == expected then
        print("MATCHES reference output")
    else
        local n = math.min(#out, #expected)
        local firstDiff = 0
        for i = 1, n do
            if out:byte(i) ~= expected:byte(i) then
                firstDiff = i
                break
            end
        end
        if firstDiff == 0 and #out ~= #expected then
            firstDiff = n + 1
        end
        print(("MISMATCH: %d vs %d bytes, first difference at %d"):format(
            #out, #expected, firstDiff))
        if firstDiff > 0 and firstDiff <= n then
            local a, b = out:byte(firstDiff), expected:byte(firstDiff)
            print(("  byte %d: got %s, want %s"):format(firstDiff, tostring(a), tostring(b)))
        end
    end
end
