const { spawn } = require('child_process');
const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const os = require('os');

const ENGINE_DIR = process.env.ENVLOGGER_DIR
    ? path.resolve(process.env.ENVLOGGER_DIR)
    : path.join(__dirname, 'envlogger');

const MAX_INPUT_BYTES = 2 * 1024 * 1024;
const MAX_CONCURRENT = 2;
let running = 0;
const DEFAULT_TIMEOUT = 25;
const KILL_GRACE_MS = 15000;

let luneCache;
function findLune() {
    if (luneCache !== undefined) return luneCache;

    const candidates = [];
    if (process.env.ENVLOGGER_LUNE) candidates.push(process.env.ENVLOGGER_LUNE);
    candidates.push('/usr/local/bin/lune', '/usr/bin/lune');
    if (process.platform === 'win32') {
        candidates.push(path.join(
            os.homedir(),
            'AppData/Local/Microsoft/WinGet/Packages',
            'Lune.Lune_Microsoft.Winget.Source_8wekyb3d8bbwe',
            'lune.exe',
        ));
    }

    for (const candidate of candidates) {
        try {
            if (fs.existsSync(candidate)) { luneCache = candidate; return luneCache; }
        } catch (_) { }
    }

    try {
        const probe = require('child_process').spawnSync('lune', ['--version'], {
            timeout: 5000, encoding: 'utf8', windowsHide: true,
        });
        if (probe.status === 0) { luneCache = 'lune'; return luneCache; }
    } catch (_) { }

    luneCache = null;
    return luneCache;
}

function isAvailable() {
    if (!fs.existsSync(path.join(ENGINE_DIR, 'src', 'main.luau'))) {
        return { ok: false, reason: `analyzer sources missing at ${ENGINE_DIR}` };
    }
    if (!findLune()) {
        return { ok: false, reason: 'the Lune runtime is not installed on this host' };
    }
    return { ok: true, reason: null };
}

async function readIfPresent(file) {
    try {
        return await fsp.readFile(file, 'utf8');
    } catch (_) {
        return null;
    }
}

async function runConstDump(content, options = {}) {
    const started = Date.now();
    const fail = (error, extra = {}) => ({
        success: false, dump: null, meta: null, error, killed: false,
        elapsed: (Date.now() - started) / 1000, ...extra,
    });

    if (typeof content !== 'string' || content.trim().length === 0) {
        return fail('There is nothing to analyze - the script is empty.');
    }
    const inputBytes = Buffer.byteLength(content, 'utf8');
    if (inputBytes > MAX_INPUT_BYTES) {
        return fail(
            `That script is ${(inputBytes / 1048576).toFixed(1)}MB. The constants engine caps input at ` +
            `${MAX_INPUT_BYTES / 1048576}MB.`,
        );
    }

    const availability = isAvailable();
    if (!availability.ok) {
        return fail(`The constants engine is unavailable: ${availability.reason}. This is a deployment problem, not a problem with your file.`);
    }
    if (running >= MAX_CONCURRENT) {
        return fail(`Too many constant dumps running right now (${running}/${MAX_CONCURRENT}). Try again in a moment.`);
    }

    const timeout = Math.max(5, Math.min(120, Number(options.timeout) || DEFAULT_TIMEOUT));
    const work = await fsp.mkdtemp(path.join(os.tmpdir(), 'omnidbf-condump-'));
    const inputPath = path.join(work, 'input.lua');
    const dumpPath = path.join(work, 'constants.lua');
    const metaPath = path.join(work, 'meta.json');
    const logPath = path.join(work, 'progress.log');

    running += 1;
    let killed = false;
    let spawnError = null;
    let exitCode = null;
    let stderr = '';

    try {
        await fsp.writeFile(inputPath, content, 'utf8');

        const childEnv = { ...process.env };
        for (const k of Object.keys(childEnv)) {
            if (/token|secret|password|webhook|private|key|auth|cookie|session|cred/i.test(k)) delete childEnv[k];
        }
        childEnv.DISCORD_TOKEN = '';
        childEnv.GROQ_API_KEY = '';

        await new Promise((resolve) => {
            const child = spawn(findLune(), [
                'run', 'src/main', '--',
                'const', inputPath,
                '--out', dumpPath,
                '--json', metaPath,
                '--log', logPath,
                '--timeout', String(timeout),
            ], {
                cwd: ENGINE_DIR,
                windowsHide: true,
                stdio: ['ignore', 'ignore', 'pipe'],
                env: childEnv,
            });

            const killer = setTimeout(() => {
                killed = true;
                try { child.kill('SIGKILL'); } catch (_) { }
            }, timeout * 1000 + KILL_GRACE_MS);

            child.stderr?.on('data', (chunk) => {
                if (stderr.length < 8192) stderr += chunk.toString('utf8');
            });
            child.on('error', (err) => { spawnError = err; });
            child.on('close', (code) => { clearTimeout(killer); exitCode = code; resolve(); });
        });

        if (spawnError) {
            return fail(`Could not start the constants engine: ${spawnError.message}. This is a deployment problem, not a problem with your file.`);
        }

        let dump = await readIfPresent(dumpPath);
        const rawMeta = await readIfPresent(metaPath);
        let meta = null;
        if (rawMeta) {
            try { meta = JSON.parse(rawMeta); } catch (_) { meta = null; }
        }

        if (!dump) {
            const progress = await readIfPresent(logPath);
            const tail = progress
                ? progress.trim().split('\n').slice(-6).join('\n')
                : null;
            const why = killed
                ? `The script ran past its ${timeout}s budget and was killed.`
                : `The constants engine exited (code ${exitCode}) without writing a dump.`;
            return fail(
                tail ? `${why}\n\nLast progress before it stopped:\n${tail}` : why,
                { killed, meta },
            );
        }

        if (killed) {
            dump += '\n-- (killed at the time budget; everything above is what it managed to recover)\n';
        }

        return {
            success: true,
            dump,
            meta,
            error: null,
            killed,
            elapsed: (Date.now() - started) / 1000,
        };
    } catch (err) {
        return fail(`The constants engine failed: ${err.message}`);
    } finally {
        running -= 1;
        await fsp.rm(work, { recursive: true, force: true }).catch(() => { });
    }
}

module.exports = { runConstDump, isAvailable, MAX_INPUT_BYTES, DEFAULT_TIMEOUT };
