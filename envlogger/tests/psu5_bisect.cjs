'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const { LuaFactory } = require('wasmoon');

(async () => {
    const lua = await new LuaFactory().createEngine();
    const body = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_rebuilt_full2.lua'), 'utf8');

    async function tryLoad(len) {
        const chunk = body.slice(0, len);
        const esc = JSON.stringify(chunk);
        const r = await lua.doString(
            `local f,e = load(${esc}, "p"); if f then return "ok" else return "bad|" .. e end`
        );
        if (r === 'ok') return { ok: true };
        return { ok: false, err: r.slice(4) };
    }

    let lo = 1, hi = body.length;
    let bestErr = null, bestAt = null;
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        const res = await tryLoad(mid);
        if (res.ok) {
            lo = mid + 1;
            continue;
        }
        if (/unfinished string/.test(res.err)) {

            lo = mid + 1;
            continue;
        }

        bestErr = res.err; bestAt = mid;
        hi = mid;
        if (hi - lo < 4) break;
    }
    console.log('first real error at offset', bestAt, ':', bestErr);
    const s = Math.max(0, bestAt - 160);
    console.log('context:', JSON.stringify(body.slice(s, bestAt + 80)));
})();
