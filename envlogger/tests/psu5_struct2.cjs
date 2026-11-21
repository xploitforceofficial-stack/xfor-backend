'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const chunkPath = path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'src', 'core', 'chunkDecoder.js');
const waPath = path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'src', 'core', 'wrapperAnalyzer.js');

const src = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_v5cand_j5.lua'), 'latin1');

(async () => {
    const chunk = await import('file://' + chunkPath.replace(/\\/g, '/'));
    const wa = await import('file://' + waPath.replace(/\\/g, '/'));
    const analysis = wa.analyzeWrapper(src);
    const tags = analysis.tags;

    const D36 = "0123456789abcdefghijklmnopqrstuvwxyz";
    const raw = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '1.lua'), 'latin1');
    const b5 = raw.slice(1022401, 1022491);
    let pos = 0; const codes = [];
    while (pos < b5.length) {
        const w = D36.indexOf(b5[pos].toLowerCase());
        if (w < 1 || pos + 1 + w > b5.length) break;
        codes.push(parseInt(b5.slice(pos + 1, pos + 1 + w).toLowerCase(), 36));
        pos += 1 + w;
    }
    const dic = Array.from({ length: 256 }, (_, i) => String.fromCharCode(i));
    let prev = null; const parts = []; let t = 256;
    for (const code of codes) {
        let e;
        if (code < dic.length) e = dic[code];
        else if (code === dic.length && prev) e = prev + prev[0];
        else break;
        parts.push(e);
        if (prev) { dic.push(prev + e[0]); t++; }
        prev = e;
    }
    const stream = Buffer.from(parts.join(''), 'latin1');
    console.log('tail stream bytes:', stream.length);

    const chunkMod = await import('file://' + chunkPath.replace(/\\/g, '/'));

    const perms = (a) => a.length <= 1 ? [a.slice()] : a.flatMap((x, i) => perms([...a.slice(0, i), ...a.slice(i + 1)]).map(r => [x, ...r]));
    const CHUNK_ORDERS = perms(["parameters", "instructions", "protos", "stack"]);
    const INSTRUCTION_ORDERS = perms(["op", "a", "b", "c"]);

    class Reader {
        constructor(buffer, key) { this.buffer = buffer; this.position = 0; this.key = key; }
        byte() { const v = this.buffer[this.position++] ^ this.key; this.key = v & 0xff; return v; }
        bytes(n) { const o = []; for (let i = 0; i < n; i++) o.push(this.byte()); return Buffer.from(o); }
        uint16() { return this.bytes(2).readUInt16LE(0); }
        uint32() { return this.bytes(4).readUInt32LE(0); }
        number() { return this.bytes(8).readDoubleLE(0); }
    }

    for (let key = 0; key < 256; key++) {
        for (const co of CHUNK_ORDERS) {
            for (const io of INSTRUCTION_ORDERS) {
                const r = new Reader(stream, key);
                try {
                    const c = chunk.decodeChunk(r, co, io, tags);
                    if (r.position === stream.length) {
                        console.log('FULL MATCH key=' + key, co.join('|'), io.join('|'));
                        console.log(JSON.stringify(c, null, 1).slice(0, 800));
                        process.exit(0);
                    }
                } catch (e) { }
            }
        }
    }
    console.log('no full match on tail stream');
})();
