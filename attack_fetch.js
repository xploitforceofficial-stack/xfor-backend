'use strict';

const assert = require('assert');
const { asu, gg, isBlockedHost, privateAddressReason } = require('./security');

const PASS = [];
const FAIL = [];

function check(name, fn) {
    return Promise.resolve()
        .then(fn)
        .then(() => { PASS.push(name); })
        .catch((e) => { FAIL.push(`${name}: ${e.message}`); });
}

async function blocked(url, why) {
    const v = asu(url);
    if (v.ok) throw new Error(`NOT blocked: ${url}`);
    if (why && !String(v.reason).toLowerCase().includes(why.toLowerCase()))
        throw new Error(`blocked but wrong reason "${v.reason}" for ${url}`);
}

async function fetchBlocked(url) {
    const r = await gg(url, { timeoutMs: 5000 });
    if (r.ok) throw new Error(`fetch succeeded on ${url}`);
}

const IP_ENCODINGS = [
    ['decimal', 'http://2130706433/'],
    ['hex', 'http://0x7f000001/'],
    ['octal', 'http://0177.0.0.1/'],
    ['mixed-octal', 'http://0177.0.0.01/'],
    ['dotted-quad-pad', 'http://127.000.000.001/'],
    ['zero-suffix', 'http://127.0.0.1.nip.io/'],
    ['ipv6-loop', 'http://[::1]/'],
    ['ipv6-v4mapped', 'http://[::ffff:127.0.0.1]/'],
    ['ipv6-compressed', 'http://[0:0:0:0:0:0:0:1]/'],
    ['nat64', 'http://[64:ff9b::7f00:0001]/'],
    ['teredo', 'http://[2001:0:0:0:0:0:7f00:0001]/'],
    ['6to4', 'http://[2002:7f00:0001::]/'],
    ['metadata-aws', 'http://169.254.169.254/latest/meta-data/'],
    ['metadata-gcp', 'http://metadata.google.internal/computeMetadata/v1/'],
    ['metadata-azure', 'http://169.254.169.254/metadata/instance'],
    ['render-internal', 'http://host.docker.internal/'],
    ['railway', 'http://railway.internal/'],
    ['k8s', 'http://kubernetes.default.svc/'],
    ['etc-passwd-scheme', 'file:///etc/passwd'],
    ['gopher', 'gopher://127.0.0.1:25/'],
    ['ftp-scheme', 'ftp://127.0.0.1/'],
    ['jar-scheme', 'jar:http://evil/!/', ],
    ['data-scheme', 'data:text/html,hi'],
    ['creds', 'http://user:pass@127.0.0.1/'],
    ['port-22', 'http://example.com:22/'],
    ['port-1337', 'http://example.com:1337/'],
    ['double-dot', 'http://example.com..evil.com/'],
    ['userinfo-trick', 'http://example.com@127.0.0.1/'],
    ['long-url', 'http://example.com/' + 'a'.repeat(3000)],
];

async function main() {
    for (const [name, url] of IP_ENCODINGS) {
        await check(`ssrf:${name}`, async () => {
            const v = asu(url);
            if (v.ok) throw new Error(`asu ACCEPTED ${url}`);
        });
    }

    await check('ssrf:blocklist-domain', () => blocked('https://webhook.site/abc'));
    await check('ssrf:blocklist-subdomain', () => blocked('https://evil.webhook.site/abc'));
    await check('ssrf:blocklist-tld', () => blocked('http://something.nip.io/x'));
    await check('ssrf:discord-blocked', () => blocked('https://discord.com/api/webhooks/123/abc'));
    await check('ssrf:ip-reflector', () => blocked('https://api.ipify.org/'));

    await check('ssrf:private-dns-rebinding-shape', async () => {

        const r = await gg('http://localhost.x127001.localhost./x', { timeoutMs: 5000 });
        if (r.ok) throw new Error('unexpected ok');
    });

    await check('good-urls-still-work', async () => {
        const ok1 = asu('https://raw.githubusercontent.com/user/repo/main/x.lua');
        if (!ok1.ok) throw new Error(`good url rejected: ${ok1.reason}`);
        const ok2 = asu('https://pastebin.com/raw/abc123');
        if (!ok2.ok) throw new Error(`good url rejected: ${ok2.reason}`);
    });

    console.log('=== FETCHER ATTACK RESULTS ===');
    console.log(`PASS: ${PASS.length}`);
    for (const f of FAIL) console.log('FAIL:', f);
    if (!FAIL.length) console.log('ALL ATTACKS DEFLECTED');
    process.exit(FAIL.length ? 1 : 0);
}
main();
