'use strict';

const {
    gg, asu, isBlockedHost, normalizeHost,
    ATTACHMENT_HOSTS, DEFAULT_MAX_BYTES,
} = require('./security');

const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';

const FALLBACK_UAS = ['RobloxStudio/WinInet', 'Roblox/WinInet'];

const MAX_REDIRECTS = 5;
const MAX_BYTES = DEFAULT_MAX_BYTES;

const TOTAL_BUDGET_MS = 25000;
const PER_HOP_MS = 10000;

const REJECTION_PHRASES = [
    'steal my source',
    'not dumpable',
    'browser access is strictly forbidden',
    'browser access',
    'this content is protected',
    'access denied',
    'not allowed to',
];

function isRejection(body) {
    if (body.length > 2048) return false;
    const lower = body.toLowerCase();
    return REJECTION_PHRASES.some(phrase => lower.includes(phrase));
}

function isHtml(body) {
    return body.includes('<!DOCTYPE') || body.includes('<html') ||
        (body.includes('<div') && body.includes('</div>'));
}

const LINK_BODY = '[^\\s"\'<>\\\\)]';

function htmlContentLink(body) {
    const patterns = [
        new RegExp(`https?://${LINK_BODY}+\\.luau?(?:\\?${LINK_BODY}*)?`, 'i'),
        new RegExp(`https?://${LINK_BODY}+/raw/${LINK_BODY}*`, 'i'),
        new RegExp(`https?://${LINK_BODY}+/raw(?:\\?${LINK_BODY}*)?(?=["'<\\s]|$)`, 'i'),
        new RegExp(`https?://${LINK_BODY}+\\.txt(?:\\?${LINK_BODY}*)?`, 'i'),
    ];
    for (const pattern of patterns) {
        const match = body.match(pattern);

        if (match) return match[0].replace(/[.,;:!]+$/, '');
    }
    return null;
}

function extractUrlFromLoadstring(text) {
    const cleaned = (text || '').trim();

    const full = cleaned.match(/loadstring\s*\(\s*game\s*:\s*Http(?:Get(?:Async)?)\s*\(\s*["']([^"']+)["']\s*\)\s*\)/i);
    if (full && full[1]) return full[1];

    const quoted = cleaned.match(/["'](https?:\/\/[^"']+)["']/i);
    if (quoted && quoted[1]) return quoted[1];
    return cleaned;
}

function normalize(url) {
    const text = extractUrlFromLoadstring((url || '').replace(/\s+/g, ''));
    if (!/^https?:\/\

    const assetMatch = text.match(/roblox\.com\/library\/(\d+)/);
    if (assetMatch) return `https://assetdelivery.roblox.com/v1/asset?id=${assetMatch[1]}`;

    const rewrites = [
        [/^https?:\/\/pastebin\.com\/(\w{8})$/i, (m) => `https://pastebin.com/raw/${m[1]}`],
        [/^https?:\/\/pastefy\.app\/([\w-]+)\/?$/i, (m) => `https://pastefy.app/${m[1]}/raw`],
        [/^https?:\/\/github\.com\/([\w][\w.-]*\/[\w][\w.-]*)\/blob\/(.+)$/i, (m) => `https://raw.githubusercontent.com/${m[1]}/${m[2]}`],
        [/^https?:\/\/rentry\.co\/([\w-]+)\/?$/i, (m) => `https://rentry.co/${m[1]}/raw`],
        [/^https?:\/\/controlc\.com\/(\w+)\/?$/i, (m) => `https://controlc.com/${m[1]}/download`],
        [/^https?:\/\/hastebin\.com\/(\w+)$/i, (m) => `https://hastebin.com/raw/${m[1]}`],
    ];
    for (const [re, build] of rewrites) {
        const m = text.match(re);
        if (m) return build(m);
    }
    return text;
}

async function fetchUrl(url, maxBytes) {
    const deadline = Date.now() + TOTAL_BUDGET_MS;
    const cap = maxBytes || MAX_BYTES;
    const start = normalize(url);

    if (start === null) {
        return { ok: false, body: null, reason: 'that is not an http or https URL', blocked: true, url: null, truncated: false };
    }

    const vetted = asu(start);
    if (!vetted.ok) {
        return { ok: false, body: null, reason: vetted.reason, blocked: true, url: null, truncated: false };
    }

    let lastHtml = null;
    let lastHtmlUrl = null;
    let lastReason = null;

    for (const userAgent of [USER_AGENT, ...FALLBACK_UAS]) {
        let current = start;
        const seen = new Set([start]);

        for (let hop = 0; hop < MAX_REDIRECTS; hop++) {
            const left = deadline - Date.now();
            if (left <= 500) {
                return {
                    ok: false, body: null, blocked: false, url: null, truncated: false,
                    reason: lastReason || 'the link did not answer in time',
                };
            }

            const res = await gg(current, {
                maxBytes: cap, userAgent,
                timeoutMs: Math.min(PER_HOP_MS, left),
            });

            if (!res.ok) {
                lastReason = res.error;

                if (res.blocked) {
                    return { ok: false, body: null, reason: res.error, blocked: true, url: null, truncated: false };
                }
                break;
            }

            const { status, body, location, truncated } = res;

            if (status >= 200 && status < 300) {
                if (isHtml(body)) {

                    if (!lastHtml) { lastHtml = body; lastHtmlUrl = current; }
                    const link = htmlContentLink(body);

                    if (link && !seen.has(link) && asu(link).ok) {
                        seen.add(link);
                        current = link;
                        continue;
                    }
                    break;
                }
                if (isRejection(body)) {
                    lastReason = 'that host refuses automated downloads';
                    break;
                }
                return { ok: true, body, reason: null, blocked: false, url: current, truncated };
            }

            if (status >= 300 && status < 400 && location) {
                let next;
                try { next = new URL(location, current).href; } catch (_) { break; }
                if (seen.has(next)) break;
                const nextVetted = asu(next);
                if (!nextVetted.ok) {

                    return {
                        ok: false, body: null, blocked: true, url: null, truncated: false,
                        reason: `that link redirects to somewhere I will not fetch - ${nextVetted.reason}`,
                    };
                }
                seen.add(next);
                current = next;
                continue;
            }

            lastReason = status ? `the link answered ${status}` : lastReason;
            break;
        }
    }

    if (lastHtml) return { ok: true, body: lastHtml, reason: null, blocked: false, url: lastHtmlUrl, truncated: false };
    return { ok: false, body: null, reason: lastReason || 'the link could not be fetched', blocked: false, url: null, truncated: false };
}

function extractFromCodeBlock(text) {
    if (typeof text !== 'string') return '';
    const match = text.match(/```(?:lua|luau|text)?\s*\n([\s\S]*?)```/);
    return match ? match[1].trim() : text.trim();
}

module.exports = { fetchUrl, extractFromCodeBlock, normalize };
