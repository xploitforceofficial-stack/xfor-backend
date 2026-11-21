'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const { LuaFactory } = require(path.join(root, 'node_modules', 'wasmoon'));

const src = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_v4_lzw_harness.lua'), 'utf8');
const envCtor = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_v4_env_constructor.lua'), 'utf8');

(async () => {
    const factory = new LuaFactory();
    const lua = await factory.createEngine();
    await lua.global.set('ENV_CTOR', envCtor);
    await lua.global.set('SRC', src);
    const out = await lua.doString(`
        local envfn = load(ENV_CTOR)
        local l = envfn()
        -- pre-fill ANY missing lookups with a strict-getmetatable so we can see which is nil:
        setmetatable(l, { __index = function(t, k) error('MISSING ENV KEY: ' .. tostring(k), 2) end })
        local chunkfn = load(SRC)
        if not chunkfn then return 'SRC LOADFAIL' end
        local harness = chunkfn()
        local R = 'This file was obfuscated using PSU Obfuscator 4.0.A | https://www.psu.dev/ & discord.gg/psu'
        local ok, res = pcall(harness, l, R)
        if not ok then return 'RUNERR: ' .. tostring(res):sub(1, 300) end
        return 'len=' .. tostring(DUMP_LEN) .. ' T=' .. tostring(DUMP_T) ..
            ' HEAD=' .. string.format('%q', DUMP_HEAD):sub(1, 220) ..
            ' TAIL=' .. string.format('%q', DUMP_TAIL):sub(1, 120)
    `);
    console.log(String(out).slice(0, 800));
})().catch(e => console.error('JSERR:', e.message.slice(0, 500)));
