'use strict';

const fs = require('fs');
const { runLuraph } = require('../luraph');

(async () => {
    const sample = process.argv[2];
    const content = fs.readFileSync(sample, 'utf8');
    const run = await runLuraph(content, { timeout: Number(process.argv[3]) || 120, notes: true });
    const m = run.meta || {};
    console.log('sample   :', sample);
    console.log('verdict  :', m.programVerdict || '(VM re-run not reached)');
    console.log('vmTrace  :', m.vmTrace, ' stages:', m.stages, ' exhausted:', m.exhausted || false);
    const text = m.finalEnvCalls || '';
    const calls = text.split(';').map((s) => s.trim()).filter(Boolean);
    console.log('env calls captured:', calls.length);
    if (!calls.length) return;
    console.log('\n--- first 16 ---');
    calls.slice(0, 16).forEach((c) => console.log('  ' + c.slice(0, 110)));

    const last = calls[calls.length - 1];
    const key = last.replace(/^#\d+\s*/, '').slice(0, 40);
    let start = calls.length - 1;
    while (start > 0 && calls[start - 1].replace(/^#\d+\s*/, '').slice(0, 40) === key) start--;
    console.log('\n--- spin: ' + (calls.length - start) + ' repeats of: ' + key);
    if (start > 0) {
        console.log('--- 8 calls before the spin ---');
        calls.slice(Math.max(0, start - 8), start).forEach((c) => console.log('  ' + c.slice(0, 110)));
    }
})();
