'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const WARN_ONLY = process.argv.includes('--warn');

const MAGIC = { dll: '\x4d\x5a', elf: '\x7fELF' };
const CHECKS = [
    ['77fuscator engine', 'deobfuscators/77fuscatorDeobf/deobfuscator.dll', 'dll'],
    ['IronBrew2 engine', 'deobfuscators/IronBrew2Deobf/ib2bot-main/ib2deobf/LuaAnalysis.Ironbrew2.dll', 'dll'],
    ['MoonSec engine', 'deobfuscators/MoonsecDeobf/bin/Release/net8.0/MoonsecDeobfuscator.dll', 'dll'],
    ['MoonSec deps manifest', 'deobfuscators/MoonsecDeobf/bin/Release/net8.0/MoonsecDeobfuscator.deps.json', 'json'],

    ['MoonSec runtimeconfig', 'deobfuscators/MoonsecDeobf/bin/Release/net8.0/MoonsecDeobfuscator.runtimeconfig.json', 'json'],
    ['MoonSec NLua binding', 'deobfuscators/MoonsecDeobf/bin/Release/net8.0/NLua.dll', 'dll'],
    ['MoonSec KeraLua binding', 'deobfuscators/MoonsecDeobf/bin/Release/net8.0/KeraLua.dll', 'dll'],
    ['MoonSec native Lua (linux-x64)', 'deobfuscators/MoonsecDeobf/bin/Release/net8.0/runtimes/linux-x64/native/liblua54.so', 'elf'],
    ['Hercules engine', 'deobfuscators/HerculesDeobf/hercules/deobfhercules_fixed/deobfhercules.py', 'py'],
    ['Delta bypass engine', 'deobfuscators/DeltaBypass/main.py', 'py'],
    ['Delta bypass auth client', 'deobfuscators/DeltaBypass/auth_client.py', 'py'],
    ['Delta bypass captcha solver', 'deobfuscators/DeltaBypass/captcha_solver.py', 'py'],
    ['Prometheus engine', 'deobfuscators/ProstoneDeobf/src/index.js', 'js'],
    ['LuaObfuscator engine', 'deobfuscators/LuaObf-Deobf/deobf.js', 'js'],
    ['Clyde engine', 'deobfuscators/clyde_static_deob.js', 'js'],
    ['Clyde reg skeleton', 'deobfuscators/clyde/regskel.js', 'js'],
    ['Goofyscator engine', 'deobfuscators/goofyscator/decompiler.py', 'py'],
    ['Goofyscator wrapper', 'deobfuscators/goofyscator_deob.js', 'js'],
    ['PSU engine', 'deobfuscators/PSU-Deobfuscator/src/deobfuscator.js', 'js'],
    ['PSU unluac', 'deobfuscators/PSU-Deobfuscator/tools/unluac.jar', 'jar'],
    ['Luraph v15 engine', 'deobfuscators/luraph_v15/deobf/deob.py', 'py'],
    ['Luraph v15 plugin', 'deobfuscators/luraph_v15/deobf/obfuscators/luraph_v15/driver.py', 'py'],
    ['Luraph v15 devirtualizer', 'deobfuscators/luraph_v15/deobf/obfuscators/luraph_v15/devirt.py', 'py'],
    ['Luraph v15 fake env', 'deobfuscators/luraph_v15/deobf/envlog.luau', 'luau'],
    ['Luraph v15 wrapper', 'deobfuscators/luraph_v15_deob.js', 'js'],
    ['Luraph v14 wrapper', 'deobfuscators/luraph_v14_deob.js', 'js'],
    ['Luraph v14 engine host', 'luraph.js', 'js'],
    ['loader helper', 'loader.js', 'js'],
    ['fetcher helper', 'fetcher.js', 'js'],
];

const problems = [];

function caseExactProblem(rel) {
    const parts = rel.split('/').filter(Boolean);
    let dir = ROOT;
    for (let i = 0; i < parts.length; i++) {
        let entries;
        try { entries = fs.readdirSync(dir); } catch (_) { return null; }
        if (!entries.includes(parts[i])) {
            const near = entries.find(e => e.toLowerCase() === parts[i].toLowerCase());
            if (near) {
                return `WRONG CASE: expected "${parts.slice(0, i + 1).join('/')}" but the directory holds "${near}" - this works on Windows and breaks on Linux`;
            }
            return null;
        }
        dir = path.join(dir, parts[i]);
    }
    return null;
}

for (const [label, rel, kind] of CHECKS) {
    const abs = path.join(ROOT, rel);
    let st;
    try { st = fs.statSync(abs); } catch (_) {
        problems.push(`${label}: MISSING  ${rel}`);
        continue;
    }
    if (!st.isFile() || st.size === 0) {
        problems.push(`${label}: EMPTY  ${rel}`);
        continue;
    }
    const wrongCase = caseExactProblem(rel);
    if (wrongCase) {
        problems.push(`${label}: ${wrongCase}`);
        continue;
    }
    if (MAGIC[kind]) {
        const want = MAGIC[kind];
        const head = Buffer.alloc(want.length);
        const fd = fs.openSync(abs, 'r');
        try { fs.readSync(fd, head, 0, want.length, 0); } finally { fs.closeSync(fd); }
        if (head.toString('binary') !== want) {
            problems.push(`${label}: NOT A ${kind.toUpperCase()} BINARY (corrupted in transit - check .gitattributes)  ${rel}`);
            continue;
        }
    }
    console.log(`ok   ${label}  (${st.size} bytes)`);
}

function checkMoonsecDeps() {
    const dir = path.join(ROOT, 'deobfuscators/MoonsecDeobf/bin/Release/net8.0');
    let deps;
    try { deps = JSON.parse(fs.readFileSync(path.join(dir, 'MoonsecDeobfuscator.deps.json'), 'utf8')); } catch (_) { return; }
    const target = deps.targets && deps.targets[Object.keys(deps.targets)[0]];
    if (!target) return;
    for (const [pkg, info] of Object.entries(target)) {
        for (const asm of Object.keys(info.runtime || {})) {
            const file = path.basename(asm);
            if (!fs.existsSync(path.join(dir, file))) {
                problems.push(`MoonSec dependency: MISSING  ${file}  (deps.json requires it for ${pkg})`);
            }
        }

        const rids = Object.keys(info.runtimeTargets || {});
        if (rids.length && !rids.some(r => r.includes('linux-x64'))) {
            problems.push(`MoonSec dependency: ${pkg} ships native assets but declares no linux-x64 RID - it cannot work on Railway.`);
        }
    }
    console.log('ok   MoonSec deps.json satisfied');
}
checkMoonsecDeps();

for (const [label, rel] of [['Prometheus', './deobfuscators/ProstoneDeobf/src/index'], ['LuaObfuscator', './deobfuscators/LuaObf-Deobf/deobf']]) {
    try {
        require(path.join(ROOT, rel));
        console.log(`ok   ${label} loads`);
    } catch (e) {
        problems.push(`${label} require failed: ${e.message}`);
    }
}

function gitCheck() {
    const { execFileSync } = require('child_process');
    const git = (args) => execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    try { git(['rev-parse', '--git-dir']); } catch (_) { return; }

    const tracked = new Set();
    const gitlinks = [];
    for (const line of git(['ls-files', '-s']).split('\n')) {
        if (!line) continue;
        const m = /^(\d{6}) [0-9a-f]+ \d+\t(.*)$/.exec(line);
        if (!m) continue;
        if (m[1] === '160000') gitlinks.push(m[2]);
        else tracked.add(m[2]);
    }
    for (const [label, rel] of CHECKS.map(c => [c[0], c[1]])) {
        if (!tracked.has(rel)) {
            let why = 'untracked';
            try { why = git(['check-ignore', '-v', rel]).trim() || 'untracked'; } catch (_) {}
            problems.push(`${label}: NOT IN GIT (${why})  ${rel}\n      Railway clones the repo, so this file will not exist in the image.`);
        }
    }
    if (gitlinks.length) {

        console.log(`\nnote: ${gitlinks.length} path(s) are committed as nested repos (mode 160000) and will be EMPTY after a clone:`);
        for (const g of gitlinks) console.log(`  ${g}`);
        console.log('  If an engine ever needs one of these, remove the inner .git and re-add the files.');
    }
}
gitCheck();

if (problems.length) {
    console.error('\n' + problems.length + ' engine problem(s):');
    for (const p of problems) console.error('  ' + p);
    console.error('\nRailway builds from git. If a file exists locally but is reported MISSING here,\nit is almost certainly untracked or ignored - check `git check-ignore -v <path>`.');
    if (!WARN_ONLY) process.exit(1);
} else {
    console.log('\nall engines present');
}
