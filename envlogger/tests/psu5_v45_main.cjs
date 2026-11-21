'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const deob = path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'src', 'deobfuscator.js');

const source = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v4.5', '1.lua'), 'latin1');

(async () => {
    const mod = await import('file://' + deob.replace(/\\/g, '/'));
    try {
        const lifted = mod.liftPsu(source);
        console.log('LIFT OK');
        console.log('stats:', JSON.stringify(lifted.stats, null, 1).slice(0, 400));
    } catch (e) {
        console.log('LIFT FAIL:', e.message);
    }
})();
