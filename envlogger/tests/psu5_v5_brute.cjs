'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const payloadMod = path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'src', 'core', 'payload.js');

const raw = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '1.lua'), 'latin1');

(async () => {
    const mod = await import('file://' + payloadMod.replace(/\\/g, '/'));

    const blob = raw.slice(439, 439 + 500000);
    const codes = mod.decodeBase36Stream ? null : null;

    const ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    const IDX = new Map();
    for (let i = 0; i < ALPHABET.length; i++) IDX.set(ALPHABET[i], i);

    function decodeBase62Stream(encoded) {
        const codes = [];
        let pos = 0;
        while (pos < encoded.length) {
            const width = IDX.get(encoded[pos]);
            pos += 1;
            if (!Number.isInteger(width) || width < 1 || pos + width > encoded.length) {
                throw new Error('bad varint at ' + pos);
            }
            let value = 0;
            for (let i = 0; i < width; i++) value = value * 62 + IDX.get(encoded[pos + i]);
            pos += width;
            codes.push(value);
        }
        return codes;
    }

    function decompressLzw(codes, seedSize) {
        const dict = Array.from({ length: seedSize }, (_, i) => String.fromCharCode(i));
        let prev = null;
        const parts = [];
        for (const code of codes) {
            let entry;
            if (code < dict.length) entry = dict[code];
            else if (code === dict.length && prev) entry = prev + prev[0];
            else throw new Error('bad LZW code ' + code + ' dict ' + dict.length);
            parts.push(entry);
            if (prev) dict.push(prev + entry[0]);
            prev = entry;
        }
        return parts.join('');
    }

    let codeList;
    try {
        codeList = decodeBase62Stream(blob);
        console.log('codes:', codeList.length, 'first 12:', codeList.slice(0, 12));
    } catch (e) {
        console.log('varint fail:', e.message);
        return;
    }

    for (const seed of [256, 91, 128, 62]) {
        try {
            const out = decompressLzw(codeList, seed);
            console.log('LZW OK seed=' + seed, 'out len:', out.length);
            console.log('first 120:', JSON.stringify(out.slice(0, 120)));
            fs.writeFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_v5_decoded.bin'), Buffer.from(out, 'latin1'));
            break;
        } catch (e) {
            console.log('seed', seed, 'fail:', e.message);
        }
    }
})();
