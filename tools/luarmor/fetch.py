"""Luarmor fetcher: follow a loader chain and save every stage.

Phase 1 established the shape: `api.luarmor.net/files/v4/loaders/<id>.lua`
returns a small `_bsdata0 = {...}` table of numbers and escaped bytes, which
itself names `cdn.luarmor.net/v4_init_sephal.lua`. So it is a chain, and the
useful code is one or two hops past the loader, not in the loader.

This walks the chain, bounded, and writes what it finds next to the samples so
it can be looked at and re-run offline.

Usage:
  python tools/luarmor/fetch.py                       # the whole links file
  python tools/luarmor/fetch.py <file.lua>            # one snippet on stdin
  python tools/luarmor/fetch.py --out DIR --key K ...
"""
import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, "..", "..", "Samples", "Luraph", "luarmor")

UA = "RobloxStudio/WinInet"
TIMEOUT = 20
MAX_BYTES = 8 * 1024 * 1024
MAX_DEPTH = 6

ALLOWED_HOSTS = {"api.luarmor.net", "cdn.luarmor.net"}

URL = re.compile(r'https?://[A-Za-z0-9.\-]+/[^\s"\'<>]+')
TRAILING_JUNK = re.compile(r'[\)\]\}.,;:"\']+$')
SCRIPT_KEY = re.compile(r'script[_-]?key\s*=\s*"([^"]*)"', re.I)

def clean_url(raw):
    """The url as the snippet means it.

    One sample is missing its closing quote, so `...24be.lua))(` arrives as part
    of the path. Cutting the path at the extension is the reliable fix rather
    than stripping a known set of trailing characters."""
    u = (raw or "").strip().strip("'\"")
    m = re.match(r'^(https?://[A-Za-z0-9.\-]+/[^\s"\'<>]*?\.(?:luau?|txt|php))', u)
    return m.group(1) if m else u

def host_of(url):
    m = re.match(r'https?://([^/]+)', url)
    return m.group(1).lower() if m else ""

def fetch(url, key=None):
    """(status, headers, body, error). `key` is sent as Luarmor's documented
    ObfuscationKey header; a load may instead want it as a query parameter, so
    the caller can retry that way."""
    if host_of(url) not in ALLOWED_HOSTS:
        return 0, {}, "", "host %r is not on the Luarmor allowlist" % host_of(url)
    headers = {"User-Agent": UA, "Accept": "*/*"}
    if key:
        headers["ObfuscationKey"] = key
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            raw = r.read(MAX_BYTES)
            return r.status, dict(r.headers), raw.decode("utf-8", "replace"), None
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers or {}), "", "HTTP %s" % e.code
    except Exception as e:
        return 0, {}, "", "%s: %s" % (type(e).__name__, e)

def urls_in(text):
    return [clean_url(u) for u in URL.findall(text or "")]

def looks_like_lua(text):
    s = (text or "").lstrip()
    return bool(s) and (s.startswith("--") or "function" in s
                        or "return" in s or "local" in s)

def sniff(name, text):
    """One line on what a fetched stage is, for the run log."""
    if not text:
        return "empty"
    if not looks_like_lua(text):
        head = " ".join(text.strip()[:120].split())
        return "not lua (looks like %s)" % head[:60]
    first = ""
    for line in text.splitlines():
        if line.strip() and not line.strip().startswith("--"):
            first = line.strip()[:70]
            break
    return "lua: %s" % first

def walk(start, key, out_dir, label):
    """Follow the chain from one loader URL. Returns (stages, seen_urls)."""
    stages = []
    queue = [(start, 0)]
    seen = {start}
    for depth in range(MAX_DEPTH):
        if not queue:
            break
        nxt = []
        for url, _d in queue:
            status, headers, body, err = fetch(url, key if depth == 0 else None)
            base = "%s_%s" % (label, os.path.basename(url).split("?")[0] or "fetched")
            rec = {"url": url, "status": status, "bytes": len(body), "depth": _d,
                   "content_type": headers.get("Content-Type"), "what": sniff(url, body),
                   "file": None, "error": err}
            if body:
                name = os.path.basename(url).split("?")[0] or "fetched"
                if not name.endswith(".lua"):
                    name += ".lua"
                path = os.path.join(out_dir, "%s_%s" % (label, name))
                with open(path, "w", encoding="utf-8", newline="\n") as f:
                    f.write(body)
                rec["file"] = os.path.basename(path)
                print("   [%d] %s -> %d bytes  %s" % (_d, os.path.basename(url), len(body), rec["what"]))
                if len(body) < 80:
                    print("        body: %s" % body.strip()[:200])
            else:
                print("   [%d] %s -> FAILED %s" % (_d, url, err))
            stages.append(rec)
            for u in urls_in(body):
                if u not in seen and host_of(u) in ALLOWED_HOSTS:
                    seen.add(u)
                    nxt.append((u, _d + 1))
        queue = nxt
    return stages, seen

def parse_links(text):
    """[(script_key, url)] from a links file or a single snippet."""
    out = []
    blocks = re.split(r'^\s*\d+\s*:\s*$', text, flags=re.M) if re.search(r'^\s*\d+\s*:\s*$', text, flags=re.M) else [text]
    for b in blocks:
        if not b.strip():
            continue
        key = SCRIPT_KEY.search(b)
        urls = urls_in(b)
        if urls:
            out.append((key.group(1) if key else "", urls[0]))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source", nargs="?", help="links file or single snippet (default: the sample links file)")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--key", default="", help="Luarmor script key, if the snippet has one")
    ap.add_argument("--depth", type=int, default=MAX_DEPTH)
    args = ap.parse_args()

    src = args.source
    if not src or not os.path.exists(src):
        src = os.path.join(HERE, "..", "..", "Samples", "Luraph", "luarmor", "luarmorlinks.txt")
    text = open(src, encoding="utf-8", errors="replace").read()
    entries = parse_links(text)
    os.makedirs(args.out, exist_ok=True)
    print("%d snippet(s) from %s\n" % (len(entries), os.path.basename(src)))

    manifest = []
    for i, (snippet_key, url) in enumerate(entries, 1):
        key = args.key or snippet_key
        print("%d. %s" % (i, url))
        print("   key: %s" % (key or "(none)"))
        stages, _seen = walk(url, key, args.out, "s%d" % i)
        manifest.append({"snippet": i, "loader": url, "key_supplied": bool(key), "stages": stages})
        print()

    with open(os.path.join(args.out, "fetch-manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
    total = sum(len(m["stages"]) for m in manifest)
    print("wrote %d stage(s) to %s" % (total, args.out))

if __name__ == "__main__":
    sys.exit(main())
