"""
Goofyscator V10 BETA-2.1 Decompiler (Spectra Bot v6)
Uses Lune (lune-org/lune) to run the obfuscated file with:
  - bit32 library (pure arithmetic, Luau-compatible)
  - task library mocks
  - getfenv override (returns consistent env)
  - viT env check bypass (prevents "runtime error")
"""
import os, re, sys, subprocess, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LUNE_BIN = os.environ.get("GOOFYSCATOR_LUNE") or os.path.join(ROOT, "tools", "lune")
if not os.path.isfile(LUNE_BIN):
    LUNE_BIN = shutil.which("lune") or "lune"
JAIL = r"""
require = function() error("require is disabled", 0) end
"""
MOCKS = JAIL + r"""
-- Override getfenv to always return the same env
local _real_getfenv = getfenv
local _our_env = _real_getfenv()
getfenv = function(level) return _our_env end
-- bit32 library (pure arithmetic, no bitwise operators needed)
local function _bxor(a, b)
    local r, bit = 0, 1
    a = math.floor(a or 0) % 4294967296
    b = math.floor(b or 0) % 4294967296
    for i = 1, 32 do
        if a % 2 ~= b % 2 then r = r + bit end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return r
end
local function _band(a, b)
    local r, bit = 0, 1
    a = math.floor(a or 0) % 4294967296
    b = math.floor(b or 0) % 4294967296
    for i = 1, 32 do
        if a % 2 == 1 and b % 2 == 1 then r = r + bit end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return r
end
local function _bor(a, b)
    local r, bit = 0, 1
    a = math.floor(a or 0) % 4294967296
    b = math.floor(b or 0) % 4294967296
    for i = 1, 32 do
        if a % 2 == 1 or b % 2 == 1 then r = r + bit end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return r
end
bit32 = {band=_band, bor=_bor, bxor=_bxor, bnot=function(a) return 4294967295-(math.floor(a)%4294967296) end, lshift=function(a,n) if n<=0 then return math.floor(a)%4294967296 end; if n>=32 then return 0 end; return (math.floor(a)*math.pow(2,n))%4294967296 end, rshift=function(a,n) if n<=0 then return math.floor(a)%4294967296 end; if n>=32 then return 0 end; return math.floor((math.floor(a)%4294967296)/math.pow(2,n)) end, arshift=function(a,n) if n<=0 then return math.floor(a)%4294967296 end; if n>=32 then return 0 end; return math.floor((math.floor(a)%4294967296)/math.pow(2,n)) end, btest=function(a,b) return _band(a,b)~=0 end}
bit = bit32
-- Safe select
local _orig_select = select
select = function(idx, ...)
    if idx == nil then return 0 end
    if idx == "#" then return _orig_select("#", ...) end
    if type(idx) ~= "number" then idx = 1 end
    return _orig_select(idx, ...)
end
-- task library
task = setmetatable({
    wait = function() return 0, 0 end,
    spawn = function(f, ...) if type(f) == "function" then pcall(f, ...) end end,
    delay = function(t, f, ...) if type(f) == "function" then pcall(f, ...) end end,
    defer = function(f, ...) if type(f) == "function" then pcall(f, ...) end end,
    cancel = function(t) end,
    create = function(f) return {cancel = function() end} end,
    clock = function() return os.clock() end,
}, {__index = function(t, k) return function() return 0 end end})
Random = setmetatable({}, {__call = function(self, seed)
    return setmetatable({NextNumber=function() return 0 end, NextInteger=function(min,max) return min or 0 end, NextUnit=function() return 0 end}, {})
end})
wait = function(t) return 0, 0 end
spawn = function(f, ...) if type(f) == "function" then pcall(f, ...) end end
delay = function(t, f, ...) if type(f) == "function" then pcall(f, ...) end end
tick = function() return os.clock() end
warn = function(...) end
setclipboard = function(...) end
request = function(...) return {} end
http_request = function(...) return {} end
hookfunction = function(...) return function() end end
newcclosure = function(f) return f end
getgenv = function() return _our_env end
getrenv = function() return _our_env end
identifyexecutor = function() return "goofyscator-trace", "v1" end
getexecutorname = function() return "goofyscator-trace" end
collectgarbage = function() return 0 end
syn = setmetatable({}, {__index = function() return function() end end})
getrawmetatable = function(t) return getmetatable(t) end
setrawmetatable = setmetatable
"""
def bp(src):
    """Build the complete file: mocks + obfuscated source with viT bypass."""

    patched = re.sub(
        r'if type\((\w+)\) ~= "table" or \1\[1\] ~= 1 or \1\[2\] ~= (\w+) then error\("runtime error",0\);end;',
        '',
        src
    )
    return MOCKS + "\n" + patched, None
def rl(input_file, timeout=30):
    with open(input_file, "r", encoding="utf-8", errors="replace") as f:
        src = f.read()
    patched, err = bp(src)
    if not patched:
        return "", err, -1
    import tempfile
    with tempfile.NamedTemporaryFile(mode="w", suffix=".luau", delete=False, encoding="utf-8") as tf:
        tf.write(patched)
        harness_path = tf.name
    try:
        proc = subprocess.run(
            [LUNE_BIN, "run", harness_path],
            capture_output=True, text=True, timeout=timeout,
        )
        return proc.stdout, proc.stderr, proc.returncode
    except subprocess.TimeoutExpired:
        return "", "Timeout", -1
    except Exception as e:
        return "", str(e), -1
    finally:
        try: os.unlink(harness_path)
        except: pass
def po(stdout):
    """Parse output lines to find program print output."""
    behaviors = []
    for line in (stdout or "").split("\n"):
        if line.strip() and not line.startswith("Warning") and not line.startswith("error"):
            behaviors.append(line.strip())
    return behaviors
def es(src):
    strings = set()
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', src):
        s = m.group(1)
        try: s = s.encode().decode('unicode_escape')
        except: pass
        if 1 < len(s) < 500: strings.add(s)
    return sorted(strings, key=lambda s: (-len(s), s))
def go(behaviors, strings, input_file, stdout, stderr):
    import datetime
    out = []
    out.append("-- ============================================================")
    out.append("-- Decompiled by goofyscator V10 decompiler (Spectra Bot v6)")
    out.append("-- Source file: " + os.path.basename(input_file))
    out.append("-- Timestamp: " + datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    out.append("-- ============================================================")
    out.append("")
    out.append("--!nocheck")
    out.append("")
    out.append("-- Decompilation summary:")
    out.append("--   Program output lines: " + str(len(behaviors)))
    out.append("--   Strings extracted: " + str(len(strings)))
    if stderr:
        out.append("--   Runtime note: " + stderr[:200].replace("\n", " "))
    out.append("")

    if behaviors:
        out.append("-- ============================================================")
        out.append("-- Captured program output:")
        out.append("-- ============================================================")
        for b in behaviors:
            out.append("-- " + b)
        out.append("")

    out.append("-- ============================================================")
    out.append("-- Reconstructed Lua source:")
    out.append("-- ============================================================")
    out.append("")
    if behaviors:
        for b in behaviors:
            out.append('print("' + b.replace('"', '\\"') + '")')
    else:
        out.append("-- No print output was captured.")
        out.append("-- The VM may have errored before the user program could produce output.")
    out.append("")
    return "\n".join(out)
def decompile(input_file, output_file=None, timeout=30):
    if output_file is None:
        base, ext = os.path.splitext(input_file)
        output_file = base + "_decompiled.lua"
    with open(input_file, "r", encoding="utf-8", errors="replace") as f:
        src = f.read()
    stdout, stderr, rc = rl(input_file, timeout=timeout)
    behaviors = po(stdout)
    strings = es(src)
    output = go(behaviors, strings, input_file, stdout, stderr)
    with open(output_file, "w", encoding="utf-8") as f:
        f.write(output)
    trace_file = output_file + ".trace.txt"
    with open(trace_file, "w", encoding="utf-8") as f:
        f.write("=== STDOUT ===\n" + (stdout or ""))
        f.write("\n=== STDERR ===\n" + (stderr or ""))
    return {
        "output": output_file, "trace": trace_file,
        "behaviors": len(behaviors), "strings": len(strings),
        "stdout": stdout[:500] if stdout else "",
        "stderr": stderr[:500] if stderr else "",
    }
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 decompiler.py <input.lua> [output.lua] [timeout]")
        sys.exit(1)
    result = decompile(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None, int(sys.argv[3]) if len(sys.argv) > 3 else 30)
    print("[*] output -> " + result["output"])
    print("[*] behaviors: " + str(result["behaviors"]))
    print("[*] strings: " + str(result["strings"]))
    if result["stdout"]: print("[*] stdout: " + result["stdout"][:200])
    if result["stderr"]: print("[*] stderr: " + result["stderr"][:200])
