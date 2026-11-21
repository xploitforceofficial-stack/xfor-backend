'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');

const raw = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '1.lua'), 'latin1');
const blob = raw.slice(439, 439 + 500000);

const A62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const IDX = new Map(A62.split('').map((c, i) => [c, i]));

let pos = 0;
const rows = [];
while (pos < 2000 && rows.length < 40) {
    const lenChar = blob[pos];
    const w = IDX.get(lenChar);
    rows.push({ pos, lenChar, w, next: blob.slice(pos + 1, pos + 1 + Math.min(w, 8)) });
    pos += 1 + (w || 1);
}
for (const r of rows) console.log(r.pos, r.lenChar, 'w=' + r.w, JSON.stringify(r.next));
