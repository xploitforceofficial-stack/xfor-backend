'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const deob = path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'src', 'deobfuscator.js');

const source = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '1.lua'), 'latin1');

(async () => {
    const mod = await import('file://' + deob.replace(/\\/g, '/'));
    try {
        const lifted = mod.liftPsu(source);
        console.log('LIFT OK');
        console.log('stats:', JSON.stringify(lifted.stats, null, 1).slice(0, 600));
        fs.writeFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_v5_bytecode.luac'), lifted.bytecode);
        console.log('bytecode bytes:', lifted.bytecode.length);
    } catch (e) {
        console.log('LIFT FAIL:', e.message);
        if (e.stack) console.log(e.stack.split('\n').slice(0, 4).join('\n'));
    }
})();
