# Luarmor v4 loaders — what the chain actually is

Research notes for `fetch.py`. Not a registered plugin: nothing here feeds the
`deobf` pipeline automatically, and nothing is wired into the bot.

## The chain

A Luarmor script is a one-line snippet. Given:

```lua
loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/<32-hex>.lua"))()
```

Two GETs are involved, and they are not the same thing.

**1. The loader** (`api.luarmor.net/files/v4/loaders/<md5>.lua`, ~1.2 KB) is
public and unauthenticated. It is short, readable Lua and looks like this:

```lua
_bsdata0={1371081282,"\164\109\57\109\127\245\213\239\177\57\143\69\149\183...",...};
local f,b,a="static_content_170926","f07dbcbe19a-sephal";
pcall(function() a=readfile(f.."/init-"..b..".lua") end)
if a and #a>2000 then a=loadstring(a) else a=nil; end;
if a then return a() else
  pcall(makefolder,f)
  a=game:HttpGet("https://cdn.luarmor.net/v4_init_sephal.lua"..(_ca920af6193 or ""))
  writefile(f.."/init-"..b..".lua", a)
  ldrupd8m=a
  return loadstring(a)(b)
end
```

Three facts worth keeping:

- **`_bsdata0` is the payload, and it is in this file.** An array of numbers
  and Lua-escaped byte strings (the escapes are `\ddd` decimal, not `\xHH`).
  It is the encrypted script, keyed by `script_key` and unpacked by the init.
  Fetching the loader is therefore fetching the payload — no further download
  is needed for it to exist on disk.
- **The CDN fetch is gated.** The loader appends `(_ca920af6193 or "")` to the
  init URL. That global is set by the *executor*, not by the script; empty
  means "unidentified client" and the CDN answers with the rejection page
  (see below).
- **The loader validates the init by size**: `if a and #a>2000`. The rejection
  page is 327 bytes, so it never even caches — it re-fetches every run.

**2. The init** (`cdn.luarmor.net/v4_init_sephal.lua`) is *not* per-script. It
is a shared unpacker/anti-tamper runtime, called as `loadstring(a)(b)` with the
per-script id `b` (`"f07dbcbe19a-sephal"`). The name is a codename, not a
version. Every sample in `Samples/Luraph/luarmor` points at the same one.

## The gate

With no executor identity the CDN returns this, verbatim:

```lua
-- If you are seeing this, it means your executor is not supported by Luarmor.
game:GetService("Players").LocalPlayer:Kick("Your executor is not supported by Luarmor. ...")
while wait(1) do end;
```

So the CDN fingerprints the client and serves the real init only to clients it
recognises as a supported executor. `fetch.py` does not attempt to satisfy that
check: it fetches the loaders (which need no credential) and reports the gate
rather than working around it.

## Getting the init legitimately

The loader caches the init to disk:

```
<executor workspace>/static_content_170926/init-f07dbcbe19a-sephal.lua
```

Both directory and file name come straight from the loader source above. Running
the snippet once in a supported executor writes it there, so it becomes an
ordinary file produced by your own licensed session. That file plus the
`script_key` is the input a deobfuscator needs — no credential is forged, and
Luarmor's own gate is left intact.

## `fetch.py`

```
python tools/luarmor/fetch.py                      # the whole links file
python tools/luarmor/fetch.py <snippet.txt>        # one snippet
python tools/luarmor/fetch.py --key <script_key>   # override the snippet's key
```

- Follows the chain, bounded at `MAX_DEPTH`, writing each stage into
  `Samples/Luraph/luarmor/` plus `fetch-manifest.json` (url, status, bytes,
  content-type, a one-line description, error).
- Host allowlist (`api.luarmor.net`, `cdn.luarmor.net`) rather than a
  blocklist: this follows whatever a fetched file points at, so the allowlist
  is the control that matters.
- Repairs snippets whose closing quote is missing. One sample in
  `luarmorlinks.txt` has `...24be.lua))()` inside the string, which naively
  parsed as part of the URL and returned an HTML `Unauthorized` page; the path
  is now cut at the extension.
- Reads `script_key` from the snippet and sends it as the `ObfuscationKey`
  header. Note the loader URLs themselves are not key-gated — all six fetched
  fine, with and without a key — so the key matters at decrypt time, not at
  fetch time.

## Measured

All 6 links, no IP block, no proxy needed, no rate limiting observed:

| link | loader | CDN init | key in snippet |
| --- | --- | --- | --- |
| 1 | 1261 B | 327 B rejection | — |
| 2 | 1249 B | 327 B rejection | `JaeDBxxgKUzbkMkIrnLlRuSmYGqZFqDH` |
| 3 | 1246 B | 327 B rejection | — |
| 4 | 1238 B | 327 B rejection | — |
| 5 | 1254 B | 327 B rejection | — |
| 6 | 1246 B | 327 B rejection | — (snippet has the broken quote) |
