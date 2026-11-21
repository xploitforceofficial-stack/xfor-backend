'use strict';

function df(content) {
    let score = 0;
    const reasons = [];
    const hit = (n, what) => { score += n; reasons.push(what); };
    if (/obfuscated with Fulcrum/i.test(content)) hit(10, 'Fulcrum watermark');
    if (/getpolsec\.com/i.test(content)) hit(8, 'getpolsec.com hosted');
    if (/pX\.NQw/.test(content)) hit(6, 'pX.NQw VM');
    if (/pX\.BVn/.test(content)) hit(4, 'pX.BVn VM');
    if (/api\.getpolsec\.com\/scripts\/hosted/.test(content)) hit(8, 'PolSec hosted API');
    return { isFulcrum: score >= 6, score, reasons };
}

function dl(content) {
    let score = 0;
    const reasons = [];
    const hit = (n, what) => { score += n; reasons.push(what); };
    if (/LuaObfuscator\.com/.test(content)) hit(10, 'LuaObfuscator.com watermark');

    if (/bit32[^\n]{0,200}bxor|bit\.bxor/.test(content)) hit(3, 'bit32/bit.bxor usage');
    if (/string\.char\([^^]{0,200}?\^[^)]{0,200}?\)/.test(content)) hit(3, 'string.char with XOR');
    if (/v\d+\("\\\d{1,3}[^"]{0,4000}",\s*"\\\d{1,3}[^"]{0,4000}"\)/.test(content)) hit(3, 'v###(escaped,escaped) string decoder');
    if (/\blocal\s+v\d+\s*=/.test(content)) hit(1, 'v-numbered locals');
    if (/while\s+true\s+do/.test(content) && /break;end/.test(content)) hit(2, 'while-butchered dispatch loop');
    return { isLuaObfuscator: score >= 5, score, reasons };
}

function dp(content) {
    let score = 0;
    const reasons = [];
    const hit = (n, what) => { score += n; reasons.push(what); };
    if (/wearedevs\.net\/obfuscator/i.test(content) || /v1\.0\.0.*wearedevs/i.test(content)) hit(10, 'wearedevs.net/obfuscator v1.0.0 watermark (Prometheus)');
    if (/return\s*\(\s*function\s*\(\s*\.\.\.\s*\)/.test(content)) hit(5, 'return (function(...) entry point');
    if (/local\s+\w+\s*=\s*\{[^}]{0,400}?\\0[0-9]{2,3}/.test(content)) hit(3, 'escaped-byte literals in a table');
    if (/ipairs\s*\(\s*\{\s*\{/.test(content)) hit(4, 'nested ipairs over tables');
    if (/return\s+\w+\[\w+\s*-\s*\d+\]/.test(content)) hit(4, 'indexed return with offset');
    if (/getfenv\s+and\s+getfenv\(\)\s*or\s+_ENV/.test(content)) hit(3, 'getfenv/_ENV fallback guard');
    if (/newproxy/.test(content)) hit(2, 'newproxy usage');

    if (/['"][A-Za-z0-9+/=]['"]\s*=\s*\d+\s*[,;]\s*['"][A-Za-z0-9+/=]['"]\s*=\s*\d+/.test(content)) hit(3, 'letter->number lookup pair');
    if (/while\s+true\s+do/.test(content)) hit(2, 'while true dispatch loop');
    return { isPrometheus: score >= 8, score, reasons };
}

const DETECTORS = [
    { type: 'fulcrum', floor: 6, run: (c) => { const r = df(c); return { pass: r.isFulcrum, score: r.score, detection: r }; } },
    { type: '77fuscator', floor: 8, run: (c) => { const { detect77fuscator } = require('./deobfuscators/77fuscator_deob'); const r = detect77fuscator(c); return { pass: r.is77fuscator, score: r.score, detection: r }; } },
    { type: 'ironbrew2', floor: 5, run: (c) => { const { detectIronBrew2 } = require('./deobfuscators/ironbrew2_deob'); const r = detectIronBrew2(c); return { pass: r.isIronBrew2, score: r.score, detection: r }; } },
    { type: 'prometheus', floor: 8, run: (c) => { const r = dp(c); return { pass: r.isPrometheus, score: r.score, detection: r }; } },
    { type: 'luaobfuscator', floor: 5, run: (c) => { const r = dl(c); return { pass: r.isLuaObfuscator, score: r.score, detection: r }; } },
    { type: 'moonsec', floor: 5, run: (c) => { const { detectMoonsec } = require('./deobfuscators/moonsec_deob'); const r = detectMoonsec(c); return { pass: r.isMoonsec, score: r.score, detection: r }; } },
    { type: 'hercules', floor: 5, run: (c) => { const { detectHercules } = require('./deobfuscators/hercules_deob'); const r = detectHercules(c); return { pass: r.isHercules, score: r.score, detection: r }; } },
    { type: 'clyde', floor: 6, run: (c) => { const { detectClyde } = require('./deobfuscators/clyde_static_deob'); const r = detectClyde(c); return { pass: r.isClyde, score: r.score, detection: r }; } },
    { type: 'ironveil', floor: 10, run: (c) => { const { detectIronveil } = require('./deobfuscators/ironveil_deob'); const r = detectIronveil(c); return { pass: r.isIronveil, score: r.score, detection: r }; } },
    { type: 'goofyscator', floor: 6, run: (c) => { const { detectGoofyscator } = require('./deobfuscators/goofyscator_deob'); const r = detectGoofyscator(c); return { pass: r.isGoofyscator, score: r.score, detection: r }; } },
    { type: 'psu', floor: 8, run: (c) => { const { detectPsu } = require('./deobfuscators/psu_deob'); const r = detectPsu(c); return { pass: r.isPsu, score: r.score, detection: r }; } },
];

const LABELS = {
    fulcrum: 'Fulcrum',
    '77fuscator': '77fuscator',
    ironbrew2: 'IronBrew 2',
    prometheus: 'Prometheus',
    luaobfuscator: 'LuaObfuscator',
    moonsec: 'MoonSec',
    hercules: 'Hercules',
    clyde: 'Clyde',
    ironveil: 'IronVeil',
    goofyscator: 'Goofyscator',
    psu: 'PSU',
};

function detectAll(content) {
    let best = null;
    for (const d of DETECTORS) {
        let r = null;
        try { r = d.run(content); } catch (_) { continue; }
        if (r && r.pass && r.score >= d.floor) {
            if (!best || r.score > best.score) {
                best = { type: d.type, label: LABELS[d.type] || d.type, score: r.score, confidence: r.score >= (d.floor * 2) ? 'high' : 'medium' };
            }
        }
    }
    return best;
}

module.exports = { df, dl, dp, DETECTORS, LABELS, detectAll };
