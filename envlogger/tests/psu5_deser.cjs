'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const raw = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '1.lua'), 'utf8');
const blob = raw.slice(439, 500439);

function makeDec(stream, n0, c0) {
    let n = n0, c = c0;
    const B = (c) => stream.charCodeAt(c - 1);
    const bx = (b) => { const r = b ^ n; n = r % 256; return r; };
    return {
        i() { const e = bx(B(c)); c += 1; return e; },
        d() { const e = bx(B(c)); const t = bx(B(c+1)); c += 2; return (t * 256) + e; },
        a() { const v1 = bx(B(c)); const v2 = bx(B(c+1)); const v3 = bx(B(c+2)); const v4 = bx(B(c+3)); c += 4; return (v4 * 16777216) + (v3 * 65536) + (v2 * 256) + v1; },
    };
}

const streams = [
    ['prefix', 'PSU|' + blob],
    ['bare', blob],
];
for (const [name, stream] of streams) {
    const c0s = name === 'prefix' ? [1, 5] : [1];
    for (const c0 of c0s) {
        const hits = [];
        for (let n0 = 0; n0 < 256; n0++) {
            const D = makeDec(stream, n0, c0);
            const M = D.d();
            const count = D.a();
            if (M > 50 && M < 100000 && count > 200 && count < 100000) {
                hits.push({ n0, M, count });
            }
        }
        console.log(`stream=${name} c0=${c0}: ${hits.length} hits`);
        hits.slice(0, 8).forEach(h => console.log('  n0=' + h.n0, 'M=' + h.M, 'consts=' + h.count));
    }
}
