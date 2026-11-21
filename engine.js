'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

const { detectMoonsec, deobfuscateMoonsec } = require('./deobfuscators/moonsec_deob');
const { detectHercules, deobfuscateHercules } = require('./deobfuscators/hercules_deob');
const { detectIronBrew2, deobfuscateIronBrew2 } = require('./deobfuscators/ironbrew2_deob');
const { detect77fuscator, deobfuscate77fuscator } = require('./deobfuscators/77fuscator_deob');
const { detectClyde, deobfuscateClyde } = require('./deobfuscators/clyde_static_deob');
const { detectIronveil, deobfuscateIronveil } = require('./deobfuscators/ironveil_deob');
const { detectGoofyscator, deobfuscateGoofyscator } = require('./deobfuscators/goofyscator_deob');
const { detectPsu, deobfuscatePsu } = require('./deobfuscators/psu_deob');
const { detectMoonVeil, deobfuscateMoonVeil } = require('./deobfuscators/moonveil_deob');
const { detectLuraphV15, deobfuscateLuraphV15 } = require('./deobfuscators/luraph_v15_deob');
const { detectLuraphV146, detectLuraphV147, detectLuraphV148, detectLuraphV149, deobfuscateLuraphV14 } = require('./deobfuscators/luraph_v14_deob');

const envlogger = require('./envlogger');
const luraph = require('./luraph');

function dp(content) {
    let score = 0;
    if (content.includes('Prometheus')) score += 10;
    if (/bit32\.bxor|bit\.bxor/.test(content)) score += 2;
    if (/\b(?:pcall|xpcall)\s*\(\s*function\s*\([^)]*\)\s*return/.test(content)) score += 3;
    if (/\b(?:getfenv|_G)\b/.test(content)) score += 1;
    return { isPrometheus: score >= 5, score };
}

function dl(content) {
    let score = 0;
    if (/LuaObfuscator\.com/i.test(content)) score += 10;
    if (/bit32[^\n]{0,200}bxor|bit\.bxor/i.test(content)) score += 3;
    if (/string\.char\([^^]{0,200}?\^[^)]{0,200}?\)/.test(content)) score += 3;
    if (/v\d+\("\\\d{1,3}[^"]{0,4000}",\s*"\\\d{1,3}[^"]{0,4000}"\)/.test(content)) score += 3;
    if (/\blocal\s+v\d+\s*=/.test(content)) score += 1;
    return { isLuaObfuscator: score >= 5, score };
}

const DETECTORS = [
    { type: '77fuscator', floor: 8, run: (c) => { const r = detect77fuscator(c); return { pass: r.is77fuscator, score: r.score, detection: r }; } },
    { type: 'ironbrew2', floor: 5, run: (c) => { const r = detectIronBrew2(c); return { pass: r.isIronBrew2, score: r.score, detection: r }; } },
    { type: 'prometheus', floor: 8, run: (c) => { const r = dp(c); return { pass: r.isPrometheus, score: r.score, detection: r }; } },
    { type: 'luaobfuscator', floor: 5, run: (c) => { const r = dl(c); return { pass: r.isLuaObfuscator, score: r.score, detection: r }; } },
    { type: 'moonsec', floor: 5, run: (c) => { const r = detectMoonsec(c); return { pass: r.isMoonsec, score: r.score, detection: r }; } },
    { type: 'hercules', floor: 5, run: (c) => { const r = detectHercules(c); return { pass: r.isHercules, score: r.score, detection: r }; } },
    { type: 'clyde', floor: 6, run: (c) => { const r = detectClyde(c); return { pass: r.isClyde, score: r.score, detection: r }; } },
    { type: 'ironveil', floor: 10, run: (c) => { const r = detectIronveil(c); return { pass: r.isIronveil, score: r.score, detection: r }; } },
    { type: 'goofyscator', floor: 6, run: (c) => { const r = detectGoofyscator(c); return { pass: r.isGoofyscator, score: r.score, detection: r }; } },
    { type: 'psu', floor: 8, run: (c) => { const r = detectPsu(c); return { pass: r.isPsu, score: r.score, detection: r }; } },
    { type: 'moonveil', floor: 8, run: (c) => { const r = detectMoonVeil(c); return { pass: r.isMoonVeil, score: r.score, detection: r }; } },
    { type: 'luraphv146', floor: 8, run: (c) => { const r = detectLuraphV146(c); return { pass: r.isLuraphV146, score: r.score, detection: r }; } },
    { type: 'luraphv147', floor: 8, run: (c) => { const r = detectLuraphV147(c); return { pass: r.isLuraphV147, score: r.score, detection: r }; } },
    { type: 'luraphv148', floor: 8, run: (c) => { const r = detectLuraphV148(c); return { pass: r.isLuraphV148, score: r.score, detection: r }; } },
    { type: 'luraphv149', floor: 8, run: (c) => { const r = detectLuraphV149(c); return { pass: r.isLuraphV149, score: r.score, detection: r }; } },
    { type: 'luraphv15', floor: 8, run: (c) => { const r = detectLuraphV15(c); return { pass: r.isLuraphV15, score: r.score, detection: r }; } },
];

const WATERMARKS = {
    '77fuscator': /77fuscator|77FUS\|/i,
    ironbrew2: /ironbrew|BytecodeEncoder/i,
    prometheus: /prometheus/i,
    luaobfuscator: /LuaObfuscator\.com/i,
    moonsec: /MoonSec/i,
    hercules: /Obfuscated by Hercules|hercules-obfuscator\.xyz|Protected By Hercules/i,
    clyde: /clydeprotectionde\.cloud|ClydeProtection/i,
    ironveil: /ironveil|LeakD/i,
    goofyscator: /goofyscator/i,
    psu: /PSU Obfuscator|psu\.dev|discord\.gg\/psu/i,
    moonveil: /moonveil\.cc|MoonVeil\s*\d|PolSec/i,
};

function detectObfuscator(content) {
    const src = String(content || '');
    const ranked = DETECTORS
        .map(d => ({ type: d.type, floor: d.floor, ...d.run(src) }))
        .filter(c => c.pass)
        .map(c => ({ ...c, watermark: (WATERMARKS[c.type] || /$^/).test(src), margin: c.score - c.floor }))
        .sort((a, b) => (Number(b.watermark) - Number(a.watermark)) || (b.margin - a.margin));

    if (!ranked.length) {
        return { type: 'unknown', score: 0, confidence: 'none', alternatives: [] };
    }
    const best = ranked[0];
    const confidence = best.watermark || best.margin >= 6 ? 'high'
        : best.margin >= 2 ? 'medium' : 'low';
    return {
        type: best.type,
        score: best.score,
        confidence,
        watermark: best.watermark,
        alternatives: ranked.slice(1, 3).map(c => c.type),
    };
}

async function deobfuscateUnified(content, requestedEngine = 'auto', filename = 'script.lua', options = {}) {
    const startTime = Date.now();
    let engine = (requestedEngine || 'auto').toLowerCase().replace(/^\./, '');

    // Map common aliases
    const aliasMap = {
        'l': 'envlogger',
        'envlog': 'envlogger',
        'envclogger': 'envlogger',
        'lph': 'luraphv15',
        'lph15': 'luraphv15',
        'lph150': 'luraphv15',
        'lph14': 'luraphv149',
        'lph146': 'luraphv146',
        'lph147': 'luraphv147',
        'lph148': 'luraphv148',
        'lph149': 'luraphv149',
        'ib': 'ironbrew2',
        'ib2': 'ironbrew2',
        'ironbrew': 'ironbrew2',
        'moon': 'moonsec',
        'moonsecv3': 'moonsec',
        '77': '77fuscator',
        'psuv4': 'psu'
    };

    if (aliasMap[engine]) {
        engine = aliasMap[engine];
    }

    let detection = null;
    if (engine === 'auto' || engine === 'deobf' || engine === 'detect') {
        detection = detectObfuscator(content);
        if (detection.type !== 'unknown') {
            engine = detection.type;
        } else {
            engine = 'envlogger'; // Fallback to envlogger behaviour trace
        }
    }

    let rawResult = null;
    try {
        switch (engine) {
            case 'envlogger':
                rawResult = await envlogger.runDump(content, { notes: true });
                if (!rawResult || !rawResult.success) {
                    // Fallback to luraph engine runner if dump fails
                    rawResult = await luraph.runLuraph(content, options);
                }
                break;
            case 'luraphv15':
                rawResult = await deobfuscateLuraphV15(content, filename);
                break;
            case 'luraphv146':
            case 'luraphv147':
            case 'luraphv148':
            case 'luraphv149':
            case 'luraphv14':
                rawResult = await deobfuscateLuraphV14(content, filename);
                break;
            case 'ironbrew2':
                rawResult = await deobfuscateIronBrew2(content);
                break;
            case 'moonsec':
                rawResult = await deobfuscateMoonsec(content);
                break;
            case 'hercules':
                rawResult = await deobfuscateHercules(content);
                break;
            case 'clyde':
                rawResult = await deobfuscateClyde(content);
                break;
            case 'ironveil':
                rawResult = await deobfuscateIronveil(content);
                break;
            case 'goofyscator':
                rawResult = await deobfuscateGoofyscator(content);
                break;
            case 'psu':
                rawResult = await deobfuscatePsu(content);
                break;
            case 'moonveil':
                rawResult = await deobfuscateMoonVeil(content, filename, options);
                break;
            case '77fuscator':
                rawResult = await deobfuscate77fuscator(content);
                break;
            default:
                // Auto fallback
                detection = detectObfuscator(content);
                if (detection.type !== 'unknown') {
                    return deobfuscateUnified(content, detection.type, filename, options);
                }
                rawResult = await envlogger.runDump(content, { notes: true });
                break;
        }
    } catch (err) {
        return {
            success: false,
            error: err.message || 'Deobfuscation engine runtime error',
            engine,
            durationMs: Date.now() - startTime
        };
    }

    const durationMs = Date.now() - startTime;
    if (!rawResult || (!rawResult.success && !rawResult.code && !rawResult.output && !rawResult.dump)) {
        return {
            success: false,
            error: rawResult?.error || 'Engine failed to produce deobfuscated code',
            engine,
            detection,
            durationMs
        };
    }

    const code = rawResult.code || rawResult.output || rawResult.dump || '';
    const lines = code ? code.split('\n').length : 0;

    return {
        success: true,
        code,
        engine,
        detection,
        stats: {
            lines,
            originalSize: content.length,
            resultSize: code.length,
            durationMs
        }
    };
}

module.exports = {
    detectObfuscator,
    deobfuscateUnified,
    DETECTORS,
    WATERMARKS
};
