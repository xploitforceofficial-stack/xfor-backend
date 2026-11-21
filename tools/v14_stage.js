'use strict';
const fs = require('fs');
const path = require('path');
const { runLuraph, DEFAULT_TIMEOUT } = require('../luraph');

const sample = process.argv[2];
const out = process.argv[3];

(async () => {
    const content = fs.readFileSync(sample, 'utf8');
    const t = Date.now();
    const run = await runLuraph(content, { timeout: DEFAULT_TIMEOUT });
    if (!run || !run.success) {
        console.error('FAIL: ' + ((run && run.error) || 'no result'));
        process.exit(1);
    }
    const files = (run.stageFiles || []).map((f) => ({ path: f.path, len: f.body.length }));
    console.error('stage files: ' + JSON.stringify(files));
    let best = null;
    for (const f of run.stageFiles || []) {
        if (!best || f.body.length > best.body.length) best = f;
    }
    if (!best) { console.error('FAIL: no stage'); process.exit(2); }
    fs.writeFileSync(out, best.body, 'utf8');
    console.error(`wrote ${out} (${best.body.length} chars, ${((Date.now() - t) / 1000).toFixed(1)}s)`);
})();
