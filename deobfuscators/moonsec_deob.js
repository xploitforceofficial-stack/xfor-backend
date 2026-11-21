'use strict';

const { getDotnetCmd } = require('./dotnet');
const { runProcess } = require('./proc');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { decompile } = require('./moonsec_decompile');
const { rp } = require('./sanitize');

const MOONSEC_EXE = path.join(__dirname, 'MoonsecDeobf', 'bin', 'Release', 'net8.0', 'MoonsecDeobfuscator.dll');

function engineStatus() {
    if (!fs.existsSync(MOONSEC_EXE)) {
        return { ok: false, error: 'MoonSec engine is not installed on this host (MoonsecDeobfuscator.dll missing). This is a deployment problem, not a problem with your file.' };
    }
    if (!getDotnetCmd()) {
        return { ok: false, error: 'The .NET 8 runtime is not available on this host, so the MoonSec engine cannot run.' };
    }
    return { ok: true };
}

function detectMoonsec(content) {
    let score = 0;
    if (/MoonSec V3/.test(content)) score += 10;
    if (/protected with MoonSec/.test(content)) score += 5;
    if (/e%0xf9c<0x7ce|e%0x2c98<0x164c/.test(content)) score += 3;
    if (/while n<\d+ do/.test(content)) score += 2;
    if (/l\[e\]=0x1/.test(content)) score += 2;
    if (/SwLvc_sQ|vweUBIrb|ZulxvfBj/.test(content)) score += 4;
    return { isMoonsec: score >= 5, score };
}

async function deobfuscateMoonsec(content) {
    const stamp = Date.now() + '_' + Math.random().toString(36).slice(2, 8);
    const tmpInput = path.join(os.tmpdir(), `moonsec_${stamp}_input.lua`);
    const tmpDis = path.join(os.tmpdir(), `moonsec_${stamp}_dis.txt`);

    const status = engineStatus();
    if (!status.ok) {
        console.error(`[MoonSec] ${status.error} (looked for ${MOONSEC_EXE})`);
        return { success: false, error: status.error };
    }

    try {
        fs.writeFileSync(tmpInput, content, 'utf8');

        const dotnet = getDotnetCmd();
        await runProcess(dotnet, [MOONSEC_EXE, '-dis', '-i', tmpInput, '-o', tmpDis], {
            timeout: 120000,
            maxBuffer: 50 * 1024 * 1024,
        });

        if (!fs.existsSync(tmpDis)) {
            try { fs.unlinkSync(tmpInput); } catch (_) {}
            return { success: false, error: 'The MoonSec engine produced no disassembly. The script is probably not MoonSec V3 output.' };
        }
        const disassembly = fs.readFileSync(tmpDis, 'utf8');

        try { fs.unlinkSync(tmpInput); } catch (_) {}
        try { fs.unlinkSync(tmpDis); } catch (_) {}

        const output = decompile(disassembly);

        const decodedStrings = [];
        const strPattern = /"([^"]{3,60})"/g;
        let match;
        while ((match = strPattern.exec(output)) !== null) {
            if (!decodedStrings.includes(match[1]) && decodedStrings.length < 20) {
                decodedStrings.push(match[1]);
            }
        }

        return {
            success: true,
            output,
            stats: {
                type: 'MoonSec V3',
                inputSize: content.length,
                outputSize: output.length,
                decodedStrings,
            },
        };
    } catch (err) {
        try { fs.unlinkSync(tmpInput); } catch (_) {}
        try { fs.unlinkSync(tmpDis); } catch (_) {}

        const stderr = err.stderr ? String(err.stderr) : '';
        const stdout = err.stdout ? String(err.stdout) : '';
        console.error(`[MoonSec] ${err.message}`);
        if (stderr) console.error('[MoonSec] stderr: ' + stderr.slice(0, 2000));
        if (stdout) console.error('[MoonSec] stdout: ' + stdout.slice(0, 2000));

        const all = rp(err.message + '\n' + stderr + '\n' + stdout);
        if (err.code === 'ETIMEDOUT' || err.signal === 'SIGTERM' || err.signal === 'SIGKILL' || /ETIMEDOUT|timed out/i.test(all)) {
            return { success: false, error: 'The MoonSec engine timed out (over 120s). The script is too large or too deeply nested.' };
        }
        if (/liblua|lua54|DllNotFoundException|Unable to load shared library/i.test(all)) {
            return { success: false, error: 'The MoonSec engine could not load its native Lua library on this host. This is a deployment problem, not a problem with your file.' };
        }
        if (/A fatal error occurred|does not exist|framework.*was not found|You must install/i.test(all)) {
            return { success: false, error: 'The MoonSec engine failed to start (.NET runtime or engine files missing). This is a deployment problem, not a problem with your file.' };
        }
        if (err.code === 'ENOENT') {
            return { success: false, error: 'Could not launch the .NET runtime for the MoonSec engine. This is a deployment problem, not a problem with your file.' };
        }
        return { success: false, error: 'MoonSec deobfuscation failed. The script may not be MoonSec V3 output, or it uses a variant the engine does not recognise.' };
    }
}

module.exports = { detectMoonsec, deobfuscateMoonsec, engineStatus, MOONSEC_EXE };
