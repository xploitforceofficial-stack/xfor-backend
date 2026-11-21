'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const raw = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '1.lua'), 'utf8');
const blob = raw.slice(439, 500439);

const DIGITS = '0123456789abcdefghijklmnopqrstuvwxyz';
const DIGITS62 = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
function parseIntB(s, base, alpha) {
    let v = 0;
    for (const ch of s) {
        const d = alpha.indexOf(ch);
        if (d < 0) return null;
        v = v * base + d;
    }
    return v;
}

function lzwV4(payload, alpha, base) {
    const w = {};
    for (let i = 0; i < 256; i++) w[i] = String.fromCharCode(i);
    let a = 256, pos = 0, e = null, out = [];
    const rd = () => {
        const len = alpha.indexOf(payload[pos]);
        if (len < 0) return null;
        const rest = payload.slice(pos + 1, pos + 1 + len);
        if (rest.length < len) return null;
        const v = parseIntB(rest, base, alpha);
        pos += 1 + len;
        return v;
    };
    let first = true;
    while (pos < payload.length) {
        const code = rd();
        if (code === null) return null;
        if (first) { e = w[code]; if (e === undefined) return null; out.push(e); first = false; continue; }
        let t;
        if (w[code] !== undefined) t = w[code];
        else if (code === a) t = e + e[0];
        else return out.join('');
        w[a] = e + t[0]; a++; e = t; out.push(t);
    }
    return out.join('');
}

function rawChars(payload) { return payload.split('').map(c => String.fromCharCode(parseIntB(c, 36, DIGITS) ?? 0)).join(''); }

function tryStream(u) {
    const hits = [];
    for (let n0 = 0; n0 < 256; n0++) {
        let n = n0, c = 0;
        const bx = (b) => { const r = b ^ n; n = r % 256; return r; };
        const B = (i) => u.charCodeAt(i);
        if (c + 2 > u.length) break;
        const M = bx(B(c)) | (bx(B(c + 1)) << 8); c += 2;
        const v1 = bx(B(c)), v2 = bx(B(c + 1)), v3 = bx(B(c + 2)), v4 = bx(B(c + 3)); c += 4;
        const count = (v4 << 24) | (v3 << 16) | (v2 << 8) | v1;
        if (M > 20 && M < 100000 && count > 50 && count < 150000) hits.push({ n0, M, count });
    }
    return hits;
}

console.log('S1 base36:', (() => { const u = lzwV4(blob, DIGITS, 36); return u ? (tryStream(u).length + ' hits, len ' + u.length) : 'decode fail'; })());
console.log('S2 base62:', (() => { const u = lzwV4(blob, DIGITS62, 62); return u ? (tryStream(u).length + ' hits, len ' + u.length) : 'decode fail'; })());
