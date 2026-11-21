'use strict';

const fs = require('fs');
const path = require('path');
const dns = require('dns');
const net = require('net');
const http = require('http');
const https = require('https');
const zlib = require('zlib');

const BLOCKLIST_FILE = process.env.OMNIDBF_BLOCKLIST
    ? path.resolve(process.env.OMNIDBF_BLOCKLIST)
    : path.join(__dirname, 'badlinks.json');

const BUILTIN_BLOCKED = [

    'ipify.org', 'api.ipify.org', 'ipinfo.io', 'ip-api.com', 'ipapi.co', 'ipapi.is',
    'ifconfig.me', 'ifconfig.co', 'icanhazip.com', 'ipecho.net', 'ident.me', 'tnedi.me',
    'myip.com', 'api.myip.com', 'whatismyipaddress.com', 'whatismyip.com', 'checkip.amazonaws.com',
    'seeip.org', 'ipv4.seeip.org', 'ip.sb', 'ipaddress.com', 'iplocation.net',
    'freegeoip.app', 'freegeoip.net', 'geoplugin.net', 'db-ip.com', 'extreme-ip-lookup.com',
    'ipgeolocation.io', 'ipwhois.io', 'ipwho.is', 'ipdata.co', 'ipstack.com', 'ipregistry.co',
    'iphub.info', 'ip2location.io', 'bigdatacloud.net', 'ipqualityscore.com', 'abstractapi.com',
    'iplogger.com', 'ipgrabber.ru', 'ipgraber.ru', 'iplis.ru', 'ipgraber.com', 'trackip.net',

    'webhook.site', 'requestbin.com', 'requestbin.net', 'pipedream.net', 'requestcatcher.com',
    'beeceptor.com', 'mockbin.org', 'hookbin.com', 'postb.in', 'typedwebhook.tools',
    'interact.sh', 'oast.pro', 'oast.live', 'oast.site', 'oast.online', 'oast.fun', 'oast.me',
    'burpcollaborator.net', 'canarytokens.com', 'canarytokens.org', 'dnslog.cn', 'ceye.io',
    'pipedream.com', 'smee.io', 'webhookrelay.com',

    'ngrok.io', 'ngrok-free.app', 'ngrok.app', 'loca.lt', 'localtunnel.me', 'serveo.net',
    'trycloudflare.com', 'telebit.io', 'pagekite.me', 'localhost.run', 'bore.pub',

    'nip.io', 'sslip.io', 'xip.io', 'localtest.me', 'lvh.me', 'vcap.me', 'fbi.com.localhost',

    'discord.com', 'discordapp.com', 'discord.gg', 'discordapp.net', 'discord.media',

    'metadata.google.internal', 'metadata.goog', 'instance-data.ec2.internal',
    'railway.internal', 'metadata.azure.com',
];

const ATTACHMENT_HOSTS = new Set([
    'cdn.discordapp.com',
    'media.discordapp.net',
    'cdn.discordapp.net',
]);

const REFLECTOR_HOSTS = new Set([
    'deviceinfo.me',
    'ifconfig.me',
    'ifconfig.co',
    'icanhazip.com',
    'api.ipify.org',
    'ipinfo.io',
    'ip-api.com',
    'checkip.amazonaws.com',
    'whatsmyip.org',
    'whatismyip.com',
    'ip.me',
    'browserleaks.com',
]);

const ALLOWED_PROTOCOLS = new Set(['http:', 'https:']);
const ALLOWED_PORTS = new Set(['', '80', '443']);

const DEFAULT_MAX_BYTES = 8 * 1024 * 1024;

const DEFAULT_TIMEOUT_MS = 12000;

const INTERNAL_HOSTNAMES = new Set([
    'host.docker.internal', 'gateway.docker.internal',
    'kubernetes.default', 'kubernetes.default.svc', 'kubernetes.default.svc.cluster.local',
    'kubernetes', 'docker.for.win.localhost', 'docker.for.mac.localhost',
    'docker-desktop', 'docker-desktop-internal',
    'metadata', 'instance-data',
]);

const INTERNAL_HOST_SUFFIXES = [
    '.svc', '.svc.cluster.local', '.internal', '.cluster.local', '.localdomain',
    '.in-addr.arpa', '.ip6.arpa',
];

function classifyEntry(raw) {
    let s = String(raw || '').trim().toLowerCase();
    if (!s) return null;

    s = s.replace(/^[a-z][a-z0-9+.-]*:\/\
    s = s.replace(/^[^/@\s]*@/, '');
    s = s.split(/[/?#\\]/)[0];

    const bracketed = s.match(/^\[([^\]]+)\]/);
    if (bracketed) s = bracketed[1];
    else if ((s.match(/:/g) || []).length < 2) s = s.replace(/:\d+$/, '');
    s = s.replace(/^\.+|\.+$/g, (m, offset) => (offset === 0 ? '.' : ''));

    const leadingDot = s.startsWith('.');
    if (leadingDot) s = s.slice(1);
    if (!s) return null;

    if (net.isIPv4(s) || net.isIPv6(s)) return { kind: 'ip', value: s };

    if (!/^[a-z0-9._-]+$/.test(s)) return null;
    if (s.length > 253) return null;

    const labels = s.split('.').filter(Boolean);
    if (labels.length === 0) return null;

    if (labels.length === 1) {
        return leadingDot ? { kind: 'tld', value: labels[0] } : { kind: 'label', value: labels[0] };
    }
    return { kind: 'domain', value: labels.join('.') };
}

let rules = null;

function loadBlocklist(force = false) {
    if (rules && !force) return rules;

    const built = {
        domains: new Set(), tlds: new Set(), labels: new Set(), ips: new Set(),
        fileEntries: 0, fileError: null, dropped: 0,
    };

    const add = (entry) => {
        const rule = classifyEntry(entry);
        if (!rule) { built.dropped += 1; return false; }
        if (rule.kind === 'domain') built.domains.add(rule.value);
        else if (rule.kind === 'tld') built.tlds.add(rule.value);
        else if (rule.kind === 'label') built.labels.add(rule.value);
        else built.ips.add(rule.value);
        return true;
    };

    for (const entry of BUILTIN_BLOCKED) add(entry);

    try {
        const parsed = JSON.parse(fs.readFileSync(BLOCKLIST_FILE, 'utf8'));
        const list = Array.isArray(parsed)
            ? parsed

            : Object.values(parsed).flat();
        for (const entry of list) {
            if (typeof entry !== 'string') { built.dropped += 1; continue; }
            if (add(entry)) built.fileEntries += 1;
        }
    } catch (err) {
        built.fileError = err.message;
        console.error(`[security] blocklist unavailable (${BLOCKLIST_FILE}): ${err.message} - ` +
            'only the built-in list is in force. This is a deployment problem.');
    }

    rules = built;
    return rules;
}

function normalizeHost(host) {
    let h = String(host || '').trim().toLowerCase();
    if (h.startsWith('[') && h.endsWith(']')) h = h.slice(1, -1);
    h = h.replace(/\.+$/, '');
    return h;
}

function isBlockedHost(host) {
    const table = loadBlocklist();
    const h = normalizeHost(host);
    if (!h) return { blocked: true, rule: 'empty host', kind: 'malformed' };

    if (net.isIP(h)) {
        if (table.ips.has(h)) return { blocked: true, rule: h, kind: 'ip' };
        return { blocked: false, rule: null, kind: null };
    }

    const labels = h.split('.').filter(Boolean);
    if (labels.length === 0) return { blocked: true, rule: 'malformed host', kind: 'malformed' };

    if (table.tlds.has(labels[labels.length - 1])) {
        return { blocked: true, rule: `.${labels[labels.length - 1]}`, kind: 'tld' };
    }
    for (const label of labels) {
        if (table.labels.has(label)) return { blocked: true, rule: label, kind: 'label' };
    }
    for (let i = 0; i < labels.length; i++) {
        const suffix = labels.slice(i).join('.');
        if (table.domains.has(suffix)) return { blocked: true, rule: suffix, kind: 'domain' };
    }
    return { blocked: false, rule: null, kind: null };
}

function privateAddressReason(ip) {
    const addr = normalizeHost(ip);

    if (net.isIPv4(addr)) {
        const p = addr.split('.').map(Number);
        if (p.some(n => !Number.isInteger(n) || n < 0 || n > 255)) return 'malformed IPv4 address';
        const [a, b] = p;
        if (a === 0) return 'this-host / unspecified (0.0.0.0/8)';
        if (a === 10) return 'private network (10.0.0.0/8)';
        if (a === 127) return 'loopback (127.0.0.0/8)';
        if (a === 100 && b >= 64 && b <= 127) return 'carrier NAT (100.64.0.0/10)';
        if (a === 169 && b === 254) {
            return addr === '169.254.169.254'
                ? 'cloud instance metadata (169.254.169.254)'
                : 'link-local (169.254.0.0/16)';
        }
        if (a === 172 && b >= 16 && b <= 31) return 'private network (172.16.0.0/12)';
        if (a === 192 && b === 168) return 'private network (192.168.0.0/16)';
        if (a === 192 && b === 0) return 'protocol assignment (192.0.0.0/24, 192.0.2.0/24)';
        if (a === 198 && (b === 18 || b === 19)) return 'benchmarking (198.18.0.0/15)';
        if (a === 198 && b === 51) return 'documentation (198.51.100.0/24)';
        if (a === 203 && b === 0) return 'documentation (203.0.113.0/24)';
        if (a >= 224) return 'multicast or reserved (224.0.0.0/4, 240.0.0.0/4)';
        return null;
    }

    if (net.isIPv6(addr)) return privateIPv6Reason(addr);
    return 'not an IP address';
}

function ipv6Groups(addr) {
    let text = addr;

    const dotted = text.match(/(\d{1,3}(?:\.\d{1,3}){3})$/);
    if (dotted) {
        const q = dotted[1].split('.').map(Number);
        if (q.some(n => !Number.isInteger(n) || n < 0 || n > 255)) return null;
        text = text.slice(0, -dotted[1].length) +
            ((q[0] << 8) | q[1]).toString(16) + ':' + ((q[2] << 8) | q[3]).toString(16);
    }

    const halves = text.split('::');
    if (halves.length > 2) return null;
    const parse = (part) => (part ? part.split(':').filter(s => s !== '') : []);
    const head = parse(halves[0]);
    const tail = halves.length === 2 ? parse(halves[1]) : [];
    if (head.length + tail.length > 8) return null;
    if (halves.length === 1 && head.length !== 8) return null;

    const groups = [
        ...head,
        ...new Array(8 - head.length - tail.length).fill('0'),
        ...tail,
    ];
    const out = [];
    for (const g of groups) {
        if (!/^[0-9a-f]{1,4}$/.test(g)) return null;
        out.push(parseInt(g, 16));
    }
    return out.length === 8 ? out : null;
}

function privateIPv6Reason(addr) {
    const g = ipv6Groups(addr);
    if (!g) return 'malformed IPv6 address';

    const allZeroButLast = g.slice(0, 7).every(x => x === 0);
    if (allZeroButLast && g[7] === 1) return 'loopback (::1)';
    if (allZeroButLast && g[7] === 0) return 'unspecified (::)';

    if (g.slice(0, 5).every(x => x === 0) && g[5] === 0xffff) return 'IPv4-mapped address (::ffff:0:0/96)';
    if (g.slice(0, 6).every(x => x === 0)) return 'IPv4-compatible address (::/96)';
    if (g[0] === 0x0064 && g[1] === 0xff9b) return 'NAT64 translation prefix (64:ff9b::/96)';
    if (g[0] === 0x2002) return '6to4 transition address (2002::/16)';
    if (g[0] === 0x2001 && g[1] === 0x0000) return 'Teredo tunnel (2001::/32)';
    if (g[0] === 0x2001 && g[1] === 0x0db8) return 'documentation (2001:db8::/32)';
    if ((g[0] & 0xfe00) === 0xfc00) return 'unique-local / private network (fc00::/7)';
    if ((g[0] & 0xffc0) === 0xfe80) return 'link-local (fe80::/10)';
    if ((g[0] & 0xff00) === 0xff00) return 'multicast (ff00::/8)';
    return null;
}

function isPrivateAddress(ip) {
    return privateAddressReason(ip) !== null;
}

function asu(raw, opts = {}) {
    const bad = (reason, rule = null) => ({ ok: false, url: null, reason, rule });
    const text = String(raw || '').trim();
    if (!text) return bad('there is no URL there');

    if (/[\s\u0000-\u001f\u007f]/.test(text)) return bad('that URL contains control characters or spaces');
    if (text.length > 2048) return bad('that URL is too long to be real');

    let url;
    try { url = new URL(text); } catch (_) { return bad('that is not a URL I can parse'); }

    if (!ALLOWED_PROTOCOLS.has(url.protocol)) {
        return bad(`only http and https are fetchable, not \`${url.protocol.replace(':', '')}\``);
    }
    if (url.username || url.password) return bad('URLs with a username or password in them are not fetched');
    if (!ALLOWED_PORTS.has(url.port)) return bad(`port ${url.port} is not a web port, so it is not fetched`);

    const host = normalizeHost(url.hostname);
    if (!host) return bad('that URL has no host');

    if (!net.isIP(host) && !host.includes('.')) {
        return bad(`\`${host}\` is not a full host name, so it is not fetched`);
    }

    if (host.includes('..') || host.startsWith('.') || host.endsWith('.')) {
        return bad(`\`${host}\` has a malformed host name, so it is not fetched`);
    }

    if (!net.isIP(host)) {
        if (INTERNAL_HOSTNAMES.has(host)) {
            return bad(`\`${host}\` is an internal host name, so it is not fetched`);
        }
        for (const suffix of INTERNAL_HOST_SUFFIXES) {
            if (host.endsWith(suffix)) {
                return bad(`\`${host}\` looks like an internal network name, so it is not fetched`);
            }
        }
    }

    if (opts.allowHosts) {
        if (!opts.allowHosts.has(host)) return bad(`\`${host}\` is not an allowed host for this operation`);
    } else {
        const blocked = isBlockedHost(host);
        if (blocked.blocked) {

            const via = blocked.rule && blocked.rule !== host ? ` (matches \`${blocked.rule}\`)` : '';
            return bad(`\`${host}\` is on the OmniDBF blocklist${via}`, blocked.rule);
        }
        for (const suffix of host.split('.').map((_, i, arr) => arr.slice(i).join('.'))) {
            if (REFLECTOR_HOSTS.has(suffix)) {
                return bad('that page only shows its visitor\'s own network/device info, not a script');
            }
        }
    }

    if (net.isIP(host)) {
        const why = privateAddressReason(host);
        if (why) return bad(`\`${host}\` is not a public address - ${why}`);
    }

    return { ok: true, url, reason: null, rule: null };
}

function safeLookup(hostname, options, callback) {
    if (typeof options === 'function') { callback = options; options = {}; }
    const opts = { ...(options || {}) };
    const wantAll = opts.all === true;

    dns.lookup(hostname, { ...opts, all: true, verbatim: true }, (err, addresses) => {
        if (err) return callback(err);

        const list = Array.isArray(addresses) ? addresses : [addresses];
        const safe = [];
        const refused = [];
        for (const entry of list) {
            const why = privateAddressReason(entry.address);
            if (why) refused.push(`${entry.address} (${why})`);
            else safe.push(entry);
        }

        if (safe.length === 0) {
            const detail = refused.length ? refused.join(', ') : 'no addresses';
            const blocked = new Error(`refusing to connect to ${hostname}: ${detail}`);
            blocked.code = 'EBLOCKEDADDR';
            return callback(blocked);
        }

        if (wantAll) return callback(null, safe);
        return callback(null, safe[0].address, safe[0].family);
    });
}

function gg(rawUrl, options = {}) {
    const maxBytes = Math.max(1024, Number(options.maxBytes) || DEFAULT_MAX_BYTES);
    const timeoutMs = Math.max(1000, Number(options.timeoutMs) || DEFAULT_TIMEOUT_MS);
    const vetted = asu(rawUrl, { allowHosts: options.allowHosts });

    if (!vetted.ok) {
        return Promise.resolve({
            ok: false, status: 0, body: '', location: null, truncated: false,
            error: vetted.reason, blocked: true, rule: vetted.rule,
        });
    }

    const url = vetted.url;
    const transport = url.protocol === 'https:' ? https : http;

    return new Promise((resolve) => {
        let settled = false;
        const finish = (result) => {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            resolve({ ok: false, status: 0, body: '', location: null, truncated: false, error: null, ...result });
        };

        const request = transport.request({
            protocol: url.protocol,
            hostname: url.hostname,
            port: url.port || (url.protocol === 'https:' ? 443 : 80),
            path: url.pathname + url.search,
            method: 'GET',
            lookup: safeLookup,

            headers: {
                'User-Agent': options.userAgent || 'Mozilla/5.0 (compatible; OmniDBF)',
                'Accept': '*/*',
                'Accept-Encoding': 'identity',
                'Connection': 'close',
            },
        });

        const timer = setTimeout(() => {
            request.destroy();
            finish({ error: `no response within ${Math.round(timeoutMs / 1000)}s` });
        }, timeoutMs);

        request.on('error', (err) => {
            const blocked = err && err.code === 'EBLOCKEDADDR';
            finish({
                error: blocked ? err.message.replace(/^refusing to connect to /, 'refused to connect to ') : `request failed (${err.code || err.message})`,
                blocked,
            });
        });

        request.on('response', (res) => collectResponse(res, {
            maxBytes, finish, url,
        }));

        request.end();
    });
}

function collectResponse(res, { maxBytes, finish, url }) {
    const status = res.statusCode || 0;
    const location = res.headers.location || null;

    const declared = Number(res.headers['content-length']);
    if (Number.isFinite(declared) && declared > maxBytes * 8) {
        res.destroy();
        return finish({
            status, location,
            error: `that response is ${(declared / 1048576).toFixed(1)}MB, which is far past the ${(maxBytes / 1048576).toFixed(0)}MB limit`,
        });
    }

    const encoding = String(res.headers['content-encoding'] || '').toLowerCase();
    let stream = res;
    if (encoding === 'gzip' || encoding === 'x-gzip') stream = res.pipe(zlib.createGunzip());
    else if (encoding === 'deflate') stream = res.pipe(zlib.createInflate());
    else if (encoding === 'br') stream = res.pipe(zlib.createBrotliDecompress());

    const chunks = [];
    let total = 0;
    let truncated = false;

    stream.on('data', (chunk) => {
        if (truncated) return;
        total += chunk.length;
        if (total > maxBytes) {
            truncated = true;

            chunks.push(chunk.subarray(0, Math.max(0, chunk.length - (total - maxBytes))));
            res.destroy();
            if (stream !== res) stream.destroy();
            return finish({ ok: true, status, location, truncated: true, body: Buffer.concat(chunks).toString('utf8') });
        }
        chunks.push(chunk);
    });

    stream.on('error', (err) => finish({
        status, location,
        error: encoding ? `could not decompress the response (${err.code || err.message})` : `transfer failed (${err.code || err.message})`,
    }));

    stream.on('end', () => finish({
        ok: true, status, location, truncated,
        body: Buffer.concat(chunks).toString('utf8'),
    }));
}

function fence(text, lang = '', limit = 1800) {
    let body = String(text == null ? '' : text);
    if (body.length > limit) body = body.slice(0, limit - 3) + '...';
    body = body
        .replace(/`/g, 'ˋ')
        .replace(/@(everyone|here)/gi, '@​$1');
    return '```' + lang + '\n' + body + '\n```';
}

function inlineSafe(text, limit = 200) {
    let s = String(text == null ? '' : text).replace(/[\u0000-\u001f\u007f]/g, '');
    if (s.length > limit) s = s.slice(0, limit - 3) + '...';
    return s.replace(/`/g, 'ˋ').replace(/@(everyone|here)/gi, '@​$1');
}
const SECRET_PATTERNS = [
    { re: /mfa\.[\w-]{84}/g, label: 'discord-mfa-token' },
    { re: /[MN][A-Za-z\d_-]{23,26}\.[A-Za-z\d_-]{6,8}\.[A-Za-z\d_-]{27,60}/g, label: 'discord-token' },
    { re: /https?:\/\/discord(?:app)?\.com\/api\/webhooks\/[\dA-Za-z]+\/[\w-]+/g, label: 'discord-webhook' },
    { re: /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----/g, label: 'private-key' },
    { re: /_+\.?ROBLOSECURITY\s*[=:]\s*([^\s;"']{20,})/gi, label: 'roblox-cookie', group: 1 },
    { re: /\b(sk_live_[A-Za-z\d]{10,}|sk_test_[A-Za-z\d]{10,}|xox[bap]-[A-Za-z\d-]{10,})/g, label: 'api-key' },
];

function ss(text) {
    let s = String(text == null ? '' : text);
    for (const { re, label, group } of SECRET_PATTERNS) {
        re.lastIndex = 0;
        if (group) {
            s = s.replace(re, (m, ...args) => {
                const val = args[group - 1];
                return m.replace(val, `[redacted:${label}]`);
            });
        } else {
            s = s.replace(re, `[redacted:${label}]`);
        }
    }
    return s;
}

const MAX_TRACKED_BUCKETS = 4096;

function crl({ capacity = 5, refillMs = 60000, name = 'op' } = {}) {
    const buckets = new Map();
    const rate = capacity / refillMs;

    const sweep = (now) => {
        for (const [key, bucket] of buckets) {
            if (bucket.tokens + (now - bucket.at) * rate >= capacity) buckets.delete(key);
        }
    };

    return {
        name,

        take(userId, cost = 1) {
            const key = String(userId || 'anonymous');
            const now = Date.now();

            let bucket = buckets.get(key);
            if (!bucket) bucket = { tokens: capacity, at: now };
            bucket.tokens = Math.min(capacity, bucket.tokens + (now - bucket.at) * rate);
            bucket.at = now;

            if (bucket.tokens < cost) {
                buckets.set(key, bucket);
                return { ok: false, retryAfterMs: Math.ceil((cost - bucket.tokens) / rate) };
            }

            bucket.tokens -= cost;
            buckets.set(key, bucket);
            if (buckets.size > MAX_TRACKED_BUCKETS) sweep(now);
            return { ok: true, retryAfterMs: 0 };
        },
        size() { return buckets.size; },
        sweep() { sweep(Date.now()); },
    };
}

function cwq({ width = 2, maxWaiting = 8, name = 'work' } = {}) {
    let active = 0;
    const waiting = [];

    const pump = () => {
        while (active < width && waiting.length > 0) {
            const job = waiting.shift();
            active += 1;
            Promise.resolve()
                .then(job.run)
                .then(job.resolve, job.reject)
                .finally(() => { active -= 1; pump(); });
        }
    };

    return {
        name,
        get active() { return active; },
        get waiting() { return waiting.length; },
        full() { return waiting.length >= maxWaiting; },

        run(job) {
            if (waiting.length >= maxWaiting) {
                const err = new Error(`too much work queued (${active} running, ${waiting.length} waiting)`);
                err.code = 'QUEUE_FULL';
                return Promise.reject(err);
            }
            return new Promise((resolve, reject) => {
                waiting.push({ run: job, resolve, reject });
                pump();
            });
        },
    };
}

function cbc({ maxBytes = 48 * 1024 * 1024, maxEntries = 200, ttlMs = 600000 } = {}) {
    const map = new Map();
    let bytes = 0;

    const sizeOf = (value) => {
        if (typeof value === 'string') return value.length;
        if (value && typeof value.content === 'string') return value.content.length;
        if (value && typeof value.output === 'string') return value.output.length;
        try { return JSON.stringify(value).length; } catch (_) { return 1024; }
    };

    const drop = (key) => {
        const entry = map.get(key);
        if (!entry) return;
        bytes -= entry.size;
        map.delete(key);
    };

    const evict = () => {

        while ((bytes > maxBytes || map.size > maxEntries) && map.size > 0) {
            drop(map.keys().next().value);
        }
    };

    return {
        set(key, value) {
            drop(key);
            const size = sizeOf(value);
            map.set(key, { value, size, at: Date.now() });
            bytes += size;
            evict();
            return this;
        },
        get(key) {
            const entry = map.get(key);
            if (!entry) return undefined;
            if (Date.now() - entry.at > ttlMs) { drop(key); return undefined; }
            return entry.value;
        },
        has(key) { return this.get(key) !== undefined; },
        delete(key) { drop(key); },
        get size() { return map.size; },
        get bytes() { return bytes; },
    };
}

function db() {
    const table = loadBlocklist();
    return {
        file: BLOCKLIST_FILE,
        fileEntries: table.fileEntries,
        fileError: table.fileError,
        builtin: BUILTIN_BLOCKED.length,
        domains: table.domains.size,
        tlds: table.tlds.size,
        labels: table.labels.size,
        ips: table.ips.size,
        dropped: table.dropped,
    };
}

module.exports = {

    loadBlocklist, isBlockedHost, db, classifyEntry, normalizeHost,

    privateAddressReason, isPrivateAddress, ipv6Groups,

    asu, safeLookup, gg, collectResponse,

    fence, inlineSafe, ss, SECRET_PATTERNS, crl, cwq, cbc,

    ATTACHMENT_HOSTS, REFLECTOR_HOSTS, ALLOWED_PORTS, DEFAULT_MAX_BYTES, DEFAULT_TIMEOUT_MS, BLOCKLIST_FILE,
};
