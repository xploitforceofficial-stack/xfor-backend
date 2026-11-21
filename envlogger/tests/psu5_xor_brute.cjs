'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const raw = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '1.lua'), 'utf8');
const blob = raw.slice(439, 500439);
const B62 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

function decode(n0) {
    let n = n0, c = 1;
    const out = [];
    const step = 1;
    const O = 256;
    for (let k = 0; k < 32; k++) {
        const ch = blob.charCodeAt(c - 1);
        if (isNaN(ch)) break;
        let e = ch ^ n;
        n = e % O;
        c += step;
        out.push(e);
    }
    return out;
}

let best = [];
for (let n0 = 0; n0 < 256; n0++) {
    const out = decode(n0);
    const printable = out.filter(b => b >= 32 && b < 127).length;
    if (printable >= 24) {
        best.push({ n0, out: out.map(b => String.fromCharCode(b)).join(''), printable });
    }
}
for (const b of best.slice(0, 12)) {
    console.log('n0=' + b.n0, JSON.stringify(b.out));
}
console.log('total candidates:', best.length);
