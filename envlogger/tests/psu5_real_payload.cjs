'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const eng = path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'src');

const src = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_v5cand_j5.lua'), 'latin1');

(async () => {
    const payload = await import('file://' + path.join(eng, 'core', 'payload.js').replace(/\\/g, '/'));
    const chunk = await import('file://' + path.join(eng, 'core', 'chunkDecoder.js').replace(/\\/g, '/'));
    const wa = await import('file://' + path.join(eng, 'core', 'wrapperAnalyzer.js').replace(/\\/g, '/'));

    let buffer;
    try {
        buffer = payload.decodePayload(src);
        console.log('payload decoded:', buffer.length, 'bytes');
    } catch (e) {
        console.log('decodePayload fail:', e.message);
        return;
    }

    const analysis = wa.analyzeWrapper(src);
    console.log('tags:', JSON.stringify(analysis.tags));

    try {
        const decoded = chunk.decodeChunkPayload(buffer, analysis.tags);
        console.log('CHUNK OK initialKey=' + decoded.initialKey, 'layout:', decoded.chunkOrder.join('|'), '/', decoded.instructionOrder.join('|'));
        console.log('constants:', decoded.chunk.constants.length, 'instrs:', decoded.chunk.instructions.length, 'protos:', decoded.chunk.protos.length);
        fs.writeFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_v5_chunk.json'),
            JSON.stringify(decoded.chunk, null, 1).slice(0, 500000));
        console.log('wrote _v5_chunk.json');
    } catch (e) {
        console.log('chunk fail:', e.message);
    }
})();
