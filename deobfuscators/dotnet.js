'use strict';

const { execFileSync } = require('child_process');
const fs = require('fs');
const { probeCommand } = require('./proc');

const CANDIDATES = [
    'dotnet',
    '/usr/bin/dotnet',
    '/usr/share/dotnet/dotnet',
    '/usr/local/share/dotnet/dotnet',
    'C:\\Program Files\\dotnet\\dotnet.exe',
];

const IS_DOTNET = /\.net/i;

function isPath(candidate) {
    return candidate.includes('/') || candidate.includes('\\');
}

function syncProbe(file, args, expect, timeoutMs) {
    try {
        const out = execFileSync(file, args, {
            timeout: timeoutMs || 5000,
            encoding: 'utf8',
            maxBuffer: 1024 * 1024,
            stdio: ['ignore', 'pipe', 'pipe'],
            windowsHide: true,
        });
        return expect ? expect.test(out || '') : true;
    } catch (_) {
        return false;
    }
}

function findDotnet() {
    for (const candidate of CANDIDATES) {
        if (isPath(candidate) && !fs.existsSync(candidate)) continue;
        if (syncProbe(candidate, ['--info'], IS_DOTNET, 5000)) return candidate;

        if (isPath(candidate) && syncProbe(candidate, ['--version'], null, 3000)) return candidate;
    }
    try {
        const which = execFileSync('which', ['dotnet'], {
            timeout: 3000, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
        }).trim();
        if (which) return which.split('\n')[0].trim();
    } catch (_) {}
    return null;
}

async function findDotnetAsync() {
    for (const candidate of CANDIDATES) {
        if (isPath(candidate) && !fs.existsSync(candidate)) continue;
        if (await probeCommand(candidate, ['--info'], IS_DOTNET, 5000)) return candidate;
        if (isPath(candidate) && await probeCommand(candidate, ['--version'], null, 3000)) return candidate;
    }
    try {
        const { runProcess } = require('./proc');
        const { stdout } = await runProcess('which', ['dotnet'], { timeout: 3000, maxBuffer: 65536 });
        const first = String(stdout || '').trim().split('\n')[0].trim();
        if (first) return first;
    } catch (_) {}
    return null;
}

let cached;

function getDotnetCmd() {
    if (cached !== undefined) return cached;
    cached = findDotnet();
    return cached;
}

let priming = null;
function primeDotnet() {
    if (cached !== undefined) return Promise.resolve(cached);
    if (!priming) {
        priming = findDotnetAsync().then((found) => {
            cached = found;
            priming = null;
            return cached;
        }, (err) => {
            cached = null;
            priming = null;
            console.error('[dotnet] probe failed:', err && err.message);
            return null;
        });
    }
    return priming;
}

function isDotnetAvailable() {
    return !!getDotnetCmd();
}

module.exports = { getDotnetCmd, isDotnetAvailable, findDotnet, findDotnetAsync, primeDotnet };
