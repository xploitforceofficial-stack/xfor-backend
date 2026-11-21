'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const upstream = path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'src', 'core', 'payload.js');

const source = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '1.lua'), 'latin1');

(async () => {
    const mod = await import('file://' + upstream.replace(/\\/g, '/'));
    try {
        const decoded = mod.decodePayload(source);
        console.log('decoded bytes:', decoded.length);
        console.log('first 200 bytes:', JSON.stringify(decoded.slice(0, 200).toString('latin1')));
        fs.writeFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_payload_decoded.bin'), decoded);
        console.log('written to _payload_decoded.bin');
    } catch (e) {
        console.log('DECODE FAIL:', e.message);
    }
})();
