'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const { LuaFactory } = require(path.join(root, 'node_modules', 'wasmoon'));

const src = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_recon5.lua'), 'utf8');

function lineate(s) {
    let out = '';
    let inStr = null;
    for (let i = 0; i < s.length; i++) {
        const c = s[i];
        out += c;
        if (inStr) {
            if (c === '\\') { out += s[i + 1] || ''; i++; }
            else if (c === inStr) inStr = null;
        } else if (c === '"' || c === "'") inStr = c;
        else if (c === ';') out += '\n';
    }
    return out;
}
const lineated = lineate(src);

(async () => {
    const factory = new LuaFactory();
    const lua = await factory.createEngine();
    await factory.mountFile('/recon5_lineated.lua', lineated);
    const out = await lua.doString(`
        local f, err = loadfile('/recon5_lineated.lua')
        if not f then return 'LOADFAIL ' .. tostring(err) end
        local frames = {}
        local function handler(e)
            for lvl = 2, 20 do
                local info = debug.getinfo(lvl, 'nSl')
                if not info then break end
                frames[#frames+1] = lvl .. ':' .. tostring(info.name or '?') .. '@L' ..
                    tostring(info.currentline)
            end
            return tostring(e) .. ' ||| ' .. table.concat(frames, ' > ')
        end
        local ok, ret = xpcall(f, handler)
        if ok then return 'OK ' .. tostring(ret) end
        return 'ERR ' .. ret
    `);
    console.log(String(out).slice(0, 2400));
})().catch(e => console.error('JSERR:', e.message.slice(0, 600)));
