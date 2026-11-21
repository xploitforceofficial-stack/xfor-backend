'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');

const raw = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '1.lua'), 'latin1');
const blob = raw.slice(439, 439 + 500000);

const ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const IDX = new Map();
for (let i = 0; i < ALPHABET.length; i++) IDX.set(ALPHABET[i], i);

function codeAt(pos) {
    const a = IDX.get(blob[pos]);
    const b = IDX.get(blob[pos + 1]);
    const c = IDX.get(blob[pos + 2]);
    if (a === undefined || b === undefined || c === undefined) return -1;
    return a * 3844 + b * 62 + c;
}

const dict = [];
for (let i = 0; i < 91; i++) dict.push(String.fromCharCode(32 + i));

let out = [];
let prev = null;
let fails = 0;

for (let pos = 0; pos + 2 < blob.length; pos += 3) {
    let code = codeAt(pos);
    if (code < 0) { fails++; out.push('?'); prev = null; continue; }

    let entry;
    if (code < dict.length) entry = dict[code];
    else if (code === dict.length && prev) entry = prev + prev[0];
    else { fails++; out.push('?'); prev = null; continue; }

    out.push(entry);
    if (prev) dict.push(prev + entry[0]);
    prev = entry;
    if (dict.length > 400000) break;
}

const text = out.join('');
console.log('fails:', fails, 'dict size:', dict.length, 'out len:', text.length);
console.log('first 400:', JSON.stringify(text.slice(0, 400)));
