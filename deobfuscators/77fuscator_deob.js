'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDotnetCmd } = require('./dotnet');
const { runProcess } = require('./proc');
const { rp } = require('./sanitize');

const DEOB_DIR = path.join(__dirname, '77fuscatorDeobf');
const DEOB_DLL = path.join(DEOB_DIR, 'deobfuscator.dll');

function detect77fuscator(content) {
    let score = 0;
    if (content.includes('77fuscator')) score += 10;
    if (content.includes('EARLY BUILD')) score += 5;
    if (/local\s+a\s*=\s*\[\[77fuscator/.test(content)) score += 5;
    if (/while true do if a<=/.test(content)) score += 2;
    if (/77FUS\|/.test(content)) score += 5;
    if (/k\(98\)\.\.k\(105\)/.test(content)) score += 2;
    return { is77fuscator: score >= 8, score };
}

async function deobfuscate77fuscator(content) {
    const tmpInput = path.join(os.tmpdir(), `77_${Date.now()}_${Math.random().toString(36).slice(2)}_input.lua`);
    const tmpOutput = path.join(os.tmpdir(), `77_${Date.now()}_${Math.random().toString(36).slice(2)}_output.luac`);

    if (!fs.existsSync(DEOB_DLL)) {
        console.error(`[77fuscator] engine missing: ${DEOB_DLL}`);
        return { success: false, error: 'The 77fuscator engine is not installed on this host (deobfuscator.dll missing). This is a deployment problem, not a problem with your file.' };
    }
    try {
        fs.writeFileSync(tmpInput, content, 'utf8');
        const dotnet = getDotnetCmd();
        if (!dotnet) {
            try { fs.unlinkSync(tmpInput); } catch (_) {}
            return { success: false, error: 'dotnet runtime not found on this host (Linux Railway needs Dockerfile with .NET 8+9).' };
        }
        try {
            await runProcess(dotnet, [DEOB_DLL, tmpInput, '-o', tmpOutput, '--strings'], { timeout: 120000, maxBuffer: 50 * 1024 * 1024 });
        } catch (e) {
            try { fs.unlinkSync(tmpInput); } catch (_) {}
            const msg = (e.stderr ? e.stderr.toString() : e.message) || '';

            if (e.code === 'ETIMEDOUT' || e.signal === 'SIGTERM' || e.signal === 'SIGKILL') {
                return { success: false, error: 'The 77fuscator engine timed out (over 2 minutes) on this script.' };
            }
            if (msg.toLowerCase().includes('dotnet') || msg.includes('not found')) return { success: false, error: '77fuscator engine failed (dotnet missing or .NET 8 not installed). Use Dockerfile.' };
            return { success: false, error: 'Deobfuscation failed. Not 77fuscator 0.6.1 or blob corrupted.' };
        }
        try { fs.unlinkSync(tmpInput); } catch (_) {}
        if (!fs.existsSync(tmpOutput)) return { success: false, error: 'Deobfuscation failed. Not 77fuscator 0.6.1.' };
        let buf;
        try { buf = fs.readFileSync(tmpOutput); } catch (_) { return { success: false, error: 'Failed to read output.' }; }
        try { fs.unlinkSync(tmpOutput); } catch (_) {}
        if (buf.length < 12 || buf.slice(0,4).toString('binary') !== '\x1bLua') return { success: false, error: 'Deobfuscator produced invalid bytecode.' };

        let proto;
        try {
            const { parseLuac } = require('./luac_parser');
            proto = parseLuac(buf);
        } catch (e) {
            return { success: false, error: `Bytecode parse failed: ${e.message}` };
        }

        let structured = null;
        const total = countInstrs(proto);
        if (total < 5000) {
            try {
                const { toLuacListing } = require('./luac_parser');
                const { decompileFromDisassembly } = require('./luac_decompile');
                const listing = toLuacListing(buf);
                structured = decompileFromDisassembly(listing);
                if (structured && structured.trim().length < 50) structured = null;
            } catch (_) { structured = null; }
        }
        let gotoLua = null;
        try {
            const { decompileBuffer } = require('./ib2_goto_decompile');
            gotoLua = decompileBuffer(buf);
            if (gotoLua && gotoLua.trim().length < 50) gotoLua = null;
        } catch (_) { gotoLua = null; }

        let output;
        let isDecompiled = false;
        if (structured && (structured.includes('return') || structured.split('\n').length > 3)) {
            output = structured;
            isDecompiled = true;
        } else if (gotoLua) {
            output = gotoLua;
            isDecompiled = true;
        } else {

            try {
                const { toLuacListing } = require('./luac_parser');
                output = toLuacListing(buf);
            } catch (_) { output = buf.toString('hex').slice(0,5000); }
        }

        output = output.split('\n').filter(l => !l.trim().startsWith('--')).join('\n').trim();
        try {
            const bitHead = /^if not bit then\s*\n\s*if bit\.bxor then\s*\n\s*if not bit32 then\s*\n\s*if bit32\.bxor then\s*\n/;
            if (bitHead.test(output)) {
                output = output.replace(bitHead, '');
                output = output.replace(/\n\s*end\s*\n\s*end\s*\n\s*end\s*\n\s*end\s*$/, '');
            }
            const lines = output.split('\n');
            let firstReturnIdx = -1;
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].trim() === 'return;') { firstReturnIdx = i; break; }
            }
            if (firstReturnIdx !== -1 && firstReturnIdx < lines.length - 1) {
                const tail = lines.slice(firstReturnIdx + 1).join('\n').trim();
                if (tail.startsWith('if not (0 <') || tail.startsWith('if (function()') || tail.startsWith('if not ({}')) {
                    output = lines.slice(0, firstReturnIdx + 1).join('\n').trim();
                }
            }
            output = output.replace(/\n\s*return;\s*$/, '').trim();
            output = output.replace(/\n{3,}/g, '\n\n').trim();

            output = output.replace(/print"([^"]+)"/g, 'print("$1")');
            output = output.replace(/print'([^']+)'/g, "print('$1')");
        } catch (_) {}
        const MAX = 7 * 1024 * 1024;
        if (output.length > MAX) output = output.slice(0, MAX);

        const decodedStrings = [];
        try { collectConstants(proto, decodedStrings); } catch (_) {}
        const clean = decodedStrings.filter(s => s.length>=3 && s.length<=60 && /^[\x20-\x7E]+$/.test(s)).slice(0,20);

        return { success: true, output, stats: { type: '77fuscator', inputSize: content.length, outputSize: output.length, decodedStrings: clean, protoCount: countProtos(proto), instrCount: total, isDecompiled } };
    } catch (err) {
        try { fs.unlinkSync(tmpInput); } catch (_) {}
        try { fs.unlinkSync(tmpOutput); } catch (_) {}
        return { success: false, error: rp(err.message || 'Unexpected error') };
    }
}

function countProtos(p){ let c=1; for(const q of p.p) c+=countProtos(q); return c; }
function countInstrs(p){ let c=p.code.length; for(const q of p.p) c+=countInstrs(q); return c; }
function collectConstants(p,out){ for(const k of p.k) if(typeof k==='string' && k.length>=3 && k.length<=60 && /^[\x20-\x7E]+$/.test(k) && !out.includes(k) && out.length<20) out.push(k); for(const q of p.p) collectConstants(q,out); }

module.exports = { detect77fuscator, deobfuscate77fuscator };
