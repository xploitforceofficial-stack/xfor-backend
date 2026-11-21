const fs = require('fs');
const path = require('path');
const v14 = require('./luraph_v14_deob');
const ROOT = path.join(__dirname, '..');

const D = [
    ['v14.6', v14.detectLuraphV146, 'isLuraphV146'],
    ['v14.7', v14.detectLuraphV147, 'isLuraphV147'],
    ['v14.8', v14.detectLuraphV148, 'isLuraphV148'],
    ['v14.9', v14.detectLuraphV149, 'isLuraphV149'],
];
const claimed = (text) => D.filter(([, fn, key]) => fn(text)[key]).map(([n]) => n);

const DIR = path.join(ROOT, 'Samples', 'Luraph');
const WANT = {
    'luraph-v14.6.lua': 'v14.6',
    'luraph-v14.7.lua': 'v14.7',
    'luraph-v14.7 (1).lua': 'v14.7',
    'luraph-v14.7 (2).lua': 'v14.7',
    'luraph-v14.7 (3).lua': 'v14.7',
    'luraph-v14.7 (4).lua': 'v14.7',
    'luraph-v14.8.lua': 'v14.8',
    'luraph-v14.9.lua': 'v14.9',
    'luraph-v15.lua': null,
    'luraph-v15 (1).lua': null,
};

let bad = 0;
console.log('--- real samples ---');
for (const [name, want] of Object.entries(WANT)) {
    const p = path.join(DIR, name);
    if (!fs.existsSync(p)) { console.log(`skip  ${name} (not present)`); continue; }
    const hits = claimed(fs.readFileSync(p, 'utf8'));
    const got = hits.length === 1 ? hits[0] : (hits.length ? hits.join(',') : null);
    const ok = got === want;
    if (!ok) bad += 1;
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${name.padEnd(22)} want=${String(want).padEnd(6)} got=${got}`);
}

console.log('\n--- other files (must not be claimed) ---');

const KNOWN_BANNERLESS = new Set([
    path.join('tools', 'work', 'stage147.lua'),
    path.join('tools', 'work', 'stage147_inst.lua'),
]);
const files = [];
(function walk(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) {
            if (e.name === 'bin' || e.name === '__pycache__') continue;
            walk(p);
        } else if (/\.luau?$/.test(e.name)) files.push(p);
    }
})(ROOT);

let scanned = 0;
for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');

    if (f.includes(`${path.sep}output${path.sep}`)) continue;
    const rel = path.relative(ROOT, f);
    if (KNOWN_BANNERLESS.has(rel)) {
        const hits = claimed(src);
        const ok = hits.length > 0;
        if (!ok) bad += 1;
        console.log(`${ok ? 'ok  ' : 'FAIL'} bannerless stage still claimed: ${rel}`);
        continue;
    }
    scanned += 1;
    const hits = claimed(src);
    if (hits.length && !/Luraph\s+Obfuscator\s+v14/i.test(src.slice(0, 4000))) {
        bad += 1;
        console.log(`FAIL CLAIMED ${hits.join(',')} : ${rel}`);
    }
}
console.log(`${scanned} file(s) scanned`);
console.log(`\n${bad} problem(s)`);
process.exit(bad ? 1 : 0);
