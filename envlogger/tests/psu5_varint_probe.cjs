'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');

const raw = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '1.lua'), 'latin1');
const blob = raw.slice(439, 439 + 500000);

const A62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const A36 = "0123456789abcdefghijklmnopqrstuvwxyz";
const IDX62 = new Map(A62.split('').map((c, i) => [c, i]));
const IDX36 = new Map(A36.split('').map((c, i) => [c, i]));

function tryStream(encoded, IDX, base, label) {
    let pos = 0, n = 0;
    const widths = [];
    while (pos < encoded.length) {
        const w = IDX.get(encoded[pos]);
        if (w === undefined) { console.log(label, 'bad len char at', pos); return; }
        pos += 1;
        if (w < 1 || pos + w > encoded.length) {
            console.log(label, 'stream ends OK after', n, 'codes; bad width', w, 'at', pos - 1);
            return;
        }
        let v = 0;
        for (let i = 0; i < w; i++) {
            const d = IDX.get(encoded[pos + i]);
            if (d === undefined) { console.log(label, 'bad digit at', pos + i); return; }
            v = v * base + d;
        }
        pos += w;
        if (n < 10) widths.push([w, v]);
        n++;
        if (v > 500000) { console.log(label, 'IMPLAUSIBLE value', v, 'at code', n, 'pos', pos); return; }
    }
    console.log(label, 'COMPLETE:', n, 'codes');
    console.log(label, 'first widths/values:', widths);
}

tryStream(blob, IDX62, 62, 'b62');
tryStream(blob, IDX36, 36, 'b36');
