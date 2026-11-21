'use strict';

const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const wa = path.join(root, 'deobfuscators', 'PSU-Deobfuscator', 'src', 'core', 'wrapperAnalyzer.js');

const src = fs.readFileSync(path.join(root, 'Samples', 'PSU', 'v5', '_v5cand_j5.lua'), 'latin1');

(async () => {
    const mod = await import('file://' + wa.replace(/\\/g, '/'));
    try {
        const analysis = mod.analyzeWrapper(src);
        console.log('ANALYZE OK');
        console.log('tags:', JSON.stringify(analysis.tags));
        console.log('handlers:', analysis.handlers.size);
        console.log('runtime enumKey:', analysis.runtime.enumKey, 'nextKey:', analysis.runtime.nextKey);
    } catch (e) {
        console.log('ANALYZE FAIL:', e.message);
    }
})();
