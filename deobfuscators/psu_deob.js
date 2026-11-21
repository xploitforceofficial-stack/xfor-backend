'use strict';

const fs = require('fs');
const path = require('path');
const { rp } = require('./sanitize');

const ENGINE_DIR = path.join(__dirname, 'PSU-Deobfuscator');
const ENGINE_ENTRY = path.join(ENGINE_DIR, 'src', 'deobfuscator.js');

function findJavaExe() {
    if (process.env.JAVA_EXE && fs.existsSync(process.env.JAVA_EXE)) return process.env.JAVA_EXE;
    const toolsDir = path.join(ENGINE_DIR, 'tools');
    try {
        for (const entry of fs.readdirSync(toolsDir)) {
            const candidate = path.join(toolsDir, entry, 'bin', 'java.exe');
            if (fs.existsSync(candidate)) return candidate;
        }
    } catch (_) {}
    return null;
}

function detectPsu(content) {
    let score = 0;

    if (/PSU Obfuscator [45]\.\d/i.test(content)) score += 12;
    else if (/psu\.dev|discord\.gg\/psu/i.test(content)) score += 6;

    if (/PSU\|[0-9A-Za-z]{50,}/.test(content)) score += 6;

    if (/return\(function\(l,\.\.\.\)local/.test(content) && /PSU\|/.test(content)) score += 3;
    if (/for l,e in pairs\(\{\(function\(e,\.\.\.\)/.test(content) && /PSU\|/.test(content)) score += 3;

    if (/#\(".*"\)\)/.test(content) && /PSU\|/.test(content)) score += 2;

    return { isPsu: score >= 8, score };
}

function detectPsuVersion(content) {
    const m = content.match(/PSU Obfuscator (\d\.\d(?:\.\d)?)/i);
    if (m) return m[1];
    return null;
}

function extractStrings(output) {
    const seen = new Set();
    const result = [];
    const pattern = /"([^"\n]{3,80})"/g;
    let m;
    while ((m = pattern.exec(output)) !== null) {
        const s = m[1];
        if (!/[a-zA-Z]/.test(s)) continue;
        if (/^[A-Za-z0-9_]{1,3}$/.test(s)) continue;
        if (seen.has(s)) continue;
        seen.add(s);
        result.push(s);
        if (result.length >= 20) break;
    }
    return result;
}

async function deobfuscatePsu(content) {
    if (!fs.existsSync(ENGINE_ENTRY)) {
        return {
            success: false,
            error: 'The PSU engine is not installed on this host (deobfuscator.js missing). '
                 + 'This is a deployment problem, not a problem with your file.',
        };
    }

    let engine;
    try {
        engine = await import('file://' + ENGINE_ENTRY.replace(/\\/g, '/'));
    } catch (err) {
        const msg = String(err && err.message || err);
        if (/Cannot find package|ERR_MODULE_NOT_FOUND/.test(msg)) {
            return {
                success: false,
                error: 'The PSU engine is missing its npm dependencies. This is a deployment problem, not a problem with your file.',
            };
        }
        return { success: false, error: rp('Failed to load the PSU engine: ' + msg.slice(0, 300)) };
    }

    if (typeof engine.deobfuscatePsu !== 'function') {
        return { success: false, error: 'The PSU engine does not export a usable entry point.' };
    }

    const javaExe = findJavaExe();
    if (!javaExe && !process.env.PSU_NO_JAVA_WARNED) {
        console.warn('psu_deob: no bundled java found, unluac step will fail if reached');
        process.env.PSU_NO_JAVA_WARNED = '1';
    }

    let result;
    try {
        result = engine.deobfuscatePsu(content, { java: javaExe || undefined, timeout: 120000 });
    } catch (err) {
        const msg = String(err && err.message || err);
        if (/unsupported instruction/i.test(msg)) {
            return {
                success: false,
                error: rp('PSU engine hit an instruction set it does not support yet: ' + msg.slice(0, 200)),
            };
        }
        if (/invalid constant|Invalid PSU/i.test(msg)) {
            return {
                success: false,
                error: rp('PSU engine could not decode this one: ' + msg.slice(0, 200)),
            };
        }
        if (/ENOENT|spawn.*java|java.*not found/i.test(msg)) {
            return {
                success: false,
                error: 'The PSU engine needs Java for the final decompile step and none was found on this host. '
                     + 'This is a deployment problem, not a problem with your file.',
            };
        }
        return { success: false, error: rp('PSU deobfuscation failed: ' + msg.slice(0, 300)) };
    }

    let output = result && result.code ? String(result.code).trim() : '';
    if (output.length === 0) {
        return { success: false, error: 'PSU deobfuscation produced empty output.' };
    }

    const MAX_OUTPUT = 7 * 1024 * 1024;
    if (output.length > MAX_OUTPUT) output = output.slice(0, MAX_OUTPUT);

    return {
        success: true,
        output,
        stats: {
            type: 'PSU',
            version: detectPsuVersion(content) || '4.x',
            inputSize: content.length,
            outputSize: output.length,
            handlers: result.stats ? result.stats.handlers : undefined,
            decodedStrings: extractStrings(output),
        },
    };
}

module.exports = { detectPsu, detectPsuVersion, deobfuscatePsu };
