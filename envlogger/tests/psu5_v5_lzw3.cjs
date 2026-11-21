'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');

const raw = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '1.lua'), 'latin1');
const blob = raw.slice(439, 439 + 500000);

const ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const IDX = new Map();
for (let i = 0; i < ALPHABET.length; i++) IDX.set(ALPHABET[i], i);

const syms = new Uint16Array(blob.length);
for (let i = 0; i < blob.length; i++) syms[i] = IDX.get(blob[i]);

function makeReader(bitsPerCode) {
    let bitPos = 0;
    const totalBits = blob.length * 6;
    return function read() {
        if (bitPos + bitsPerCode > totalBits) return -1;
        let val = 0;
        for (let b = 0; b < bitsPerCode; b++) {
            const symIdx = Math.floor(bitPos / 6);
            const bitInSym = 5 - (bitPos % 6);
            const bit = (syms[symIdx] >> bitInSym) & 1;
            val = (val << 1) | bit;
            bitPos++;
        }
        return val;
    };
}

function tryLzw(bitsPerCode, firstOffset) {
    const read = makeReader(bitsPerCode);
    for (let i = 0; i < firstOffset; i++) read();

    const dict = [];
    for (let i = 0; i < 256; i++) dict.push(String.fromCharCode(i));
    let prev = null, fails = 0, outLen = 0;
    const out = [];

    for (let k = 0; k < 100000; k++) {
        const code = read();
        if (code < 0) break;
        let entry;
        if (code < dict.length) entry = dict[code];
        else if (code === dict.length && prev) entry = prev + prev[0];
        else { fails++; break; }
        out.push(entry);
        outLen += entry.length;
        if (prev) dict.push(prev + entry[0]);
        prev = entry;
        if (fails > 0) break;
    }
    return { fails, outLen, text: out.join('') };
}

for (const bits of [9, 10, 11, 12, 13, 16]) {
    for (const skip of [0, 1, 2, 4, 8]) {
        const r = tryLzw(bits, skip);
        if (r.fails === 0 && r.outLen > 0) {
            console.log(`BITS=${bits} skip=${skip}: OK! outLen=${r.outLen}`);
            console.log('  first 200:', JSON.stringify(r.text.slice(0, 200)));
        }
    }
}
console.log('done');
