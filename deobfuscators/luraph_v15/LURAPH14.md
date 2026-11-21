# Luraph v14.x — findings

Reference, not a changelog. What is measured on the sample set and what is
still open. Everything here was read off a recovered stage or the sandbox's own
trace output, not assumed.

## Status: all 8 v14 samples deobfuscate to real source

`python deobf/deob.py <sample> --obfuscator luraph_v14` writes two files into
`<input folder>/output/`: `<name>.luau` (the recovered stage + its dispatch
tables) and **`<name>.deobf.luau` (the readable reconstruction — the one to
look at)**.

| Sample | Loader shape | Statements | Status |
| --- | --- | --- | --- |
| `luraph-v14.7 (3).lua` | inline stage | **825** | finished |
| `luraph-v14.6.lua` | LZ loader, 70,782 B stage | 142 | spin-abort |
| `luraph-v14.7 (2).lua` | zstd loader, 92,731 B stage | 130 | spin-abort |
| `luraph-v14.7.lua` | inline stage | 107 | spin-abort |
| `luraph-v14.8.lua` | inline stage | 100 | spin-abort |
| `luraph-v14.7 (1).lua` | inline stage | 10 | finished |
| `luraph-v14.7 (4).lua` | LZ loader, 69,359 B stage | 9 | finished |
| `luraph-v14.9.lua` | LZ loader, 76,040 B stage | 54 | spin-abort |

"spin-abort" is the watchdog, not a failure: the run builds its whole GUI tree,
then the user payload enters a silent `while true` loop (an event-wait). The
trace so far is the complete reconstruction of what the script *does*; only
callback bodies that never ran are missing. The header of each file says so.

**The four that used to time out now work.** The three fixes, all general:

1. **The stage must be instrumented before it runs.** An uninstrumented v14
   stage is a pure-VM endless loop: the tracer sees nothing and the run is
   killed with a loader-only trace. The stage comes from one of three places,
   tried in order:
   - `zblobs.build_map` — LPH frames + host zstd, for zstd loaders.
   - the source itself — v14.7 base and v14.8 ship the VM closure table as the
     whole file (`INLINE_STAGE`), no loader and no `loadstring` at all.
   - a first capture run — the LZ loaders `loadstring` the stage, and
     `envlog.luau` now reports each chunk **the moment it is loadstring'd**
     rather than in a batch at the end, so even a killed run hands it over.
     Chunks are read from `harness.LAST_RAW`, not the body, for that reason.
2. **Instrument every loop shape, not just `while true do`.** v14 builds put
   the dispatch loop in `while <cond> do` and `repeat ... until false` as well
   (v14.7: 66 `while true do`, 32 conditional, 54 repeat; v14.9's stage goes
   from 65 to 173 heads). Missing those spins just as silently.
   `scope.inject_spin_all(..., conditional=True, repeats=True)`.
3. **A killed run must keep what it printed.** `harness._communicate` used to
   raise `TimeoutExpired` and throw the captured output away. It now attaches
   the partial output, and `run_once` salvages the trace from it. This is the
   same "keep the trace so far" contract the budget abort already had.

## The recovered stage is the VM runtime, not the user's code

The stage opens as a closure table:

```lua
local R=...;return({RY=function(Y,Y,c)Y=c[4438];return Y;end,rJ=math.ceil,
OY=function(Y,Y,c,F)Y[c]=F;end,t6=fu...
```

The user's script exists only as the sealed program blob that runtime
interprets. The dispatch has two layers.

**Step wrapper** — a method call that rewrites four state slots per step and
loops with `until false`:

```lua
local F,A,C,Q=(103); repeat A,F,Q,C=Y:z6(c,F,Q); if A==-2 then return C; end; until false
```

`Y:z6` is the step function, `A == -2` the halt sentinel. The four slot names
are per-build; `Q` is the state/program counter in the sampled builds.

**Interpreter** — a flat dispatch on that state:

```lua
while true do
  if Q==8.0 then Q=(71); for l=1.0,#F[45],3.0 do ... end; continue;
  elseif Q==102.0 then Q=(13); j=F[46](H); continue;
  ...
```

State values are floats used as opcode tags (`8`, `13`, `29`, `51`, `54`, `60`,
`71`, `102`, `106`, `107`, `115`, `145`, `18205`, `49462` observed). `F[45]` is
the register file, `F[46]` the constant/opcode table. A `while X do` form
(`V6`, ~offset 3538) loops on `A==18205` / `A==49462`, so **tag values are not
globally unique across functions**.

## A tag is not an opcode, it is scoped to its chain

`obfuscators/luraph_v14/isa.py` walks every `if X==tag` / `elseif X==tag` chain
in a decrypted stage and groups the arms by state slot. `luraph-v14.7 (4)` has
**17 separate dispatch chains** (47 arms down to 9). Two consequences:

- `8` in one chain is a *different instruction* from `8` in another. A table
  transcribed from one sample and applied to another reads authoritatively and
  is wrong — that is why `isa.py` derives every table from the stage in front
  of it and reports all chains rather than picking one.
- The chain a trace instruments is not the widest one. "Biggest chain = the
  interpreter" is wrong; the widest is just the widest.

`isa.py` also records, per tag, the tags its arms transition to, so control flow
is recoverable statically before any execution.

The runtime trace records the state tag only — `a`..`e` are nil on every row,
so it has no operands. `scope.py` fixes that on the AST: parse with `luau-ast`,
walk to every `while` whose body dispatches on `state == tag`, take the loop's
scope from the enclosing block's preceding `local` statements, and inject at an
offset the AST reports. On the `(4)` stage: **22 loops across 8 state slots**,
+1,086 bytes, and the patched stage still reparses.

```
state Q    tags [8, 102, 13]    ops ['l', 'A', 'C', 'H', 'j']
state F    tags [60]            ops ['A']
state g    tags [62, 5, 27]     ops []
```

Two things the AST settled that patterns could not:

- **luau-ast lines are 0-based** with byte-offset columns (`offsets[line]`, not
  `offsets[line - 1]`). Getting this wrong inserts mid-keyword.
- **The stage is `return({f = function() ... end})`**, so every interpreter
  closure sits inside a table-constructor *expression*. A statement-only walk
  finds 0 loops against 964 `AstStatIf` present; the walk must descend into
  expressions.

A pattern cannot do this. Tying a `local a,b,c;` list back to its loop needs a
non-greedy span that crosses function boundaries in this layout, injects
out-of-scope names, and the stage stops running:

```
regex attempt:  302741ms, 3322 operations  ->  5955ms, 0 operations
```

Because the scope decision is per block, the AST walk cannot leak across
function boundaries. `test_scope.py` covers scope isolation, no false positives
on plain Luau, the five-operand cap, and the real stage. Its real-stage case
keys on the *hottest* chain (most dispatch arms), not on a state-slot name or a
tag list: those are per-build — the s2 hot chain is `q` with tags 20/46/99, the
canonical one `Q` with 8/13/102 — so naming either would only ever test one
sample.

## The program buffer is decoded (proven, not guessed)

From `Samples/Luraph/luraph-v14.7 (4).lua`, verified numerically — the counts
are exact and the cross-checks disagree zero times. The stage never mentions
`buffer.` by name; it captures the readers while initialising, so
`tools/capture_program.luau` wraps `buffer.readu8` etc. before the sample loads.
Extracted by `tools/v14_stage.js` (`tools/work/stage147.lua`, 69,359 chars),
runnable standalone with `tools/run_stage.luau` — no brotli, seconds instead of
the ~300 s the loader's pure-Lua decompressor costs.

| offset | contents |
| --- | --- |
| 0 | varint count `H` = `71374` (`ce ad 04`) |
| 3 | flag byte `C` = `0` |
| 4 .. 7096 | 1222 constant-pool records, ends exactly at `H` |
| 7097 .. 106971 | instruction stream, 69,475 varints, tiles the rest exactly |

`H - 70152 = 1222` records, each `tag` + payload: tags <= 73 are f32, 74 is
u32 x2, 75..88 i32, 89..98 none, 99..157 i16, 158..182 u16, 183..215 u32,
216..228 and 243 u8, 229..242 and 244..255 a 7-bit-varint-length string.
Varints are 7-bit little-endian. Cross-checks clean: the greedy parse lands on
exactly 1222 records at 7097; all 756 typed reads in the read log are claimed
by a pool record, zero mismatches.

`tools/patch_stage.py` instruments `g6`, the header reader the per-instruction
loop calls, and `tools/decode_stream.py` aligns it with the varint stream:
**17,023 headers, 17,023 aligned, 0 mismatches.** Each header is three varints
read in order `A`, `Y`, `H`; a fourth is read by `w6` and folded into the row.
Typical width is 4 varints (16,853 of them), the rest 7-14, with one
639-varint outlier. Per instruction `tools/work/gy.tsv` records `K = A % 8`
and `Z = floor(A / 8)` (tagged operand), `op` from the `w6` varint `% 8`, `J`
the raw varint, and `H`/`T`/`G`. `K` selects in `GY`: 6 = load `state[9][Z]`,
5 = `EY`, 7 = relative `w + Z`, 2 = `XY`, 0 = `KY` (append to `F[45]`), 3 = no
operand (9,964 of 17,023). The same tag set drives `dY` and `mY`, which append
the three-element entries `sY` later replays:

```lua
for l = 1, #F[45], 3 do F[45][l][F[45][l+1]] = j[F[45][l+2]] end
```

## The opcode table exists: one leaf per opcode

`aY` calls `A[50]` once per pool entry, so the program is 1222 loaded blocks.
What runs is **192 chains**: instrumenting `A[49]` shows 192 entries, chain
lengths 6..645 (19,179 slots), each holding parallel arrays — `t` is the opcode
array, `i`/`f`/`O`/`v` the operand arrays.

`A[49]`'s dispatch is `local P = t[G]` followed by a binary search over `P`
(the junk state `M = 75` is constant-foldable). Running to the first Roblox API
call gives **515,733 dispatches over 158 distinct P values** in 1..196, skewed:
94 (35%), 149 (22%), then 80/17/73/97/6/74/65/90. ~50 opcodes carry >1000 hits.

`tools/a49_dispatch.py` folds the junk and emits `tools/work/opcodes/<P>.lua`.
Three things make it fall out: `local M = 75` is fixed for the whole dispatch,
so every `M == k` test with `k ~= 75` folds and the real dispatch sits in the
arm `M == 75` selects; the `P` tests are plain (`P<98`, `not(P<49)`, `P==97`,
`P~=161`), so a concrete opcode picks a unique path; and where a test is opaque
(`A[26]~=A[17]`, `d[i[G]]==O[G]`), the arm that keeps dispatching on `P` is the
spine, else both sides are emitted labelled `-- if ... then` / `-- else`.

Result: **158 leaves, and every one of the 515,733 dispatches lands on a leaf
that contains code.** 35.7% of dispatch weight sits under an ambiguous test, but
in the hot cases (149, 65, 80, 155) both sides are state-field junk while the
real register effect sits outside the test.

| P | executed | code |
| --- | --- | --- |
| 94 | 179,406 | `G = D[G]` unconditional jump |
| 149 | 111,816 | `d[w[G]] = d[i[G]]` register move |
| 80 | 21,174 | `G = w[G]` conditional jump |
| 17 | 19,276 | `d[D[G]] = f[G]` load immediate |
| 73 | 17,270 | `G = i[G]` conditional jump |
| 97 | 13,586 | `K = {...}; for p = 1, D[G] do d[p] = K[p] end` varargs to registers |
| 65 | 11,094 | `d[K+1] = q; d[K] = q[O[G]]`, `K = i[G]`, `q = d[w[G]]` |
| 174 | 10,954 | `d[D[G]] = d[w[G]][z[G]]` index |
| 6 | 12,065 | `n = n[g]; K[q] = n` store |

The chain descriptor `H` behind `A[49]` unpacks to the parallel arrays a lifter
reads per slot: `O=H[1] z=H[2] v=H[5] f=H[6] t=H[7] w=H[8] i=H[9] D=H[11]`,
`d = A[46](v)`, `local P = t[G]`.

## Lift pipeline (offline, per workdir)

```
python tools/deob14.py tools/work       # canonical family
python tools/deob14.py tools/work_s2    # multi-loop family
```

`deob14.json` grades each build `failed` / `dispatch-only` / `user-level` from
what landed, so a partial recovery is never reported clean.

| Sample | Family | Leaves | Chains / slots | Jump validation | `simple.lua` |
| --- | --- | --- | --- | --- | --- |
| `luraph-v14.7 (4)` | canonical | 208 | 192 / 19,172 | 709/723 = **0.981** | 21 complete, 54 approx, 117 partial; 390 statements |
| `luraph-v14.7 (2)` | s2 (3 loops) | 197 | 177 / 16,565 | 4/4 | 12 approx, 165 partial; 12 statements |

**The two families need different leaf syntax, and one pipeline.** The chain
schema is positional, so only the *names* differ: canonical uses pc register
`G`, registers `d`, operand arrays `t,i,w,D,f,O,z`; s2 uses pc `F`, registers
`r`, arrays `m,N,h,y,f,d,n`. `lift14.detect_profile` picks one from a marker in
`op.tsv` (s2 rows carry a loop tag) or an explicit `profile.json`, and renames
s2 leaves into canonical shape on load. Renaming is one whole-identifier pass,
so a target name that is also a source name cannot cascade.

**Why s2's jump validation is weak.** Its 177 chains are clones of one
descriptor, so a `(slot, opcode)` pair usually matches several chains with
*different* operands. `validate14` only counts a slot when every candidate
agrees, leaving 4 testable transitions. A data limit, not a decoder bug;
distinguishing clones needs live chain identity per dispatch.

**Folding the s2 dispatch tree needs the runtime `z` table.** The dispatcher's
branch decisions test `z[..]`, which are neither literals nor registers.
`patch_s2.py` snapshots them once (`zstate.tsv`) and `a49_dispatch.py --zstate`
folds against them; the values are run-stable, so they decide paths
authoritatively. Without the snapshot most leaves come out as the wrong arm —
the single biggest quality difference between the two families.

**Two bugs worth remembering** (both were silent):
- A leaf's dispatch increment (`G+=1.0`) rides along on non-jumping leaves. In
  place, it pushes a one-line jump leaf past the single-statement check, so
  *every* jump classifies as a plain statement and nothing lifts.
- Column 9 of a chain row was filled from the chain *length* instead of the `n`
  array. In s2 that array is genuinely empty, so the field is honest but unused
  — check the array before assuming a data bug.

## The register array is the VM's env table, not bytecode

Tested and false, and worth keeping because it looks true. The register array
the instrumenter captures (e.g. `A[4]`, 1,219 slots) has 1,002 numeric values
spanning `-4294964638 .. 4503599627370496` (2^32 and 2^52 sentinels), 749
distinct, only 6.4% in a plausible opcode range, 499 ascending against 502
descending steps — random order, no pc walk. Its non-numeric entries are the
VM's *own* library references (`loadstring`, `getinfo`, `rawset`, `__index`,
`coroutine`). It is the runtime's environment table, and what it holds is the
VM's 15-operation primitive set (`A[4][5|6|8|9|10|11|12|13|14|15|16|17|19|20|22]`,
364 call sites) used to compute **its own** dispatch through chained range
tests. `n=(4503599627370495)` is `2^52 - 1`, a NaN-boxing sentinel.

`A[4]` is a polymorphic state slot: a fresh table at one point (`l[4] = ({})`),
a number at others (`(A)[4] = 13`). The table is **not built anywhere in the
source** — zero `[4] = function` / `[4] = Y:fn(` assignments, zero `rawset(` /
`setmetatable(` that could fill it, only 6 function-slot assignments in the
whole stage (indices 32, 36, 41, 43, 47, 50 — the VM's own helpers), no fill
loop. The 15 handlers are **created at runtime by the VM's decoder**; they are
not in the text and cannot be read statically. Getting their semantics means
capturing the decoded table mid-run and probing each handler behaviourally, or
instrumenting the decoder itself. (This stopped being the wall: the dispatch
leaves above already name the semantics, and the *run* now reaches the user's
code directly.)

## Detection

`deobfuscators/luraph_v14_deob.js` offers one entry per minor (14.6 - 14.9).
With a version banner a file matches exactly one entry - the only reliable way
to tell them apart, since they differ in loader shape and not in anything a
shell pattern pins down (14.7 and 14.8 both ship the VM as the whole file;
14.6, 14.7 and 14.9 all use the LZ loader).

**Without a banner, v14 has to show its own shape**: the VM closure table
(`return({name=function`, either shipped as the whole file or reached through
the loader) plus the step wrapper, and an `LPH` marker. That is what catches
`tools/work/stage147.lua`, a recovered stage with no banner.

What must **not** count as evidence: `loadstring`, `load(`, and a generic
`function(...) ... loadstring` wrapper. Hercules, MoonSec and ordinary scripts
have all three, and scoring them claimed **9 Hercules samples as v14.6** - small
readable files with a polyfill header that were then handed back as a
"deobfuscation" of code that was never obfuscated. Claiming a file is worse
than missing one; the menu still offers every version by hand.

`node deobfuscators/luraph_v14_detect_check.cjs` covers both halves: each sample
on its own version with v15 unclaimed, and nothing else in the repo claimed.

## Stage decompression

The loaders decompress the sealed stage through a fake `EncodingService`.
`(2)` uses **zstd**, `(4)` and `(6)`/`(7)`/`(8)`/`(9)` an inline LZ decompressor.

The pure-Luau zstd decoder (`envlogger/src/env/zstd.luau`) is correct for raw,
RLE and short literal-only frames but **not** for compressed-Huffman/FSE
literals: 9/23 of the known-answer corpus (`python tools/zstd_gen.py` +
`lune run tools/zstd_corpus.luau`). Rather than depend on it,
`EncodingService:Decompress` falls back to a real implementation on the host
(`envlogger/zstd_host.py`, `zstandard`) whenever the pure decoder errors or
returns nothing, memoized per frame. That is what unblocked `(2)`: from failing
at `invalid zstd input` to 3 stages. If the decoder ever passes the corpus,
drop `hostZstd` from `envlogger/src/env/services.luau` — it shells out to
Python, which the bot host does not guarantee.

The v15 harness has the same fallback: `zblobs.py` pre-decodes LPH frames with
`zstandard` on the host and `harness.build_harness` emits them as base64
`__ZSTD` (base64 because raw binary breaks the lexer), which
`envlog.luau`'s `DecompressBuffer` serves. `(2)` resolves to 92,731 (stage) and
2,153,271 (program) bytes; the host-decompressed stage is byte-identical to
`tools/work_s2/stage.lua`, chunk key `92731_504239268`.

**Lune is still too slow for this.** The v14 VM is bytecode interpreted *inside*
Lune, so under the full fake environment `(2)` exhausts even a 1800 s budget
with zero dispatches logged. The v15 `luau.exe` harness runs the same stage in
19-53 s, which is why every v14 sample now completes.

## What the four stalled samples actually are

`(2)`, 14.6, 14.7 base, 14.8 and 14.9 stop partway through building an offscreen
instance tree, having made no game, service or network call at all, and never
reach the `ChildAdded`/`GetChildren` block that `(3)` passes. The statement
count is **invariant to the budget** (spin 30 and spin 300 both give 14.9
exactly 54 statements), so it is not a slow run or a huge junk loop: the VM
stops calling the environment and never comes back. That is the documented
shape of a failed anti-tamper check - a silent busy loop.

A completed `(3)` from another tool is identical to ours (1134 statements, zero
unique to either side) and *also* shows the Path2D probe and the junk GUI, so
neither is by itself evidence of tampering. What separates a complete run is
reaching `GetService`, network calls and signal connections afterwards.

Not yet identified: which check fails. The candidates are a float-precision
value the runtime computes differently from the engine - the Path2D probe feeds
exactly that arithmetic - or a stand-in that answers where the real thing
errors. Telling them apart needs Studio ground truth for the Path2D answers,
so this is open rather than fixed.

### Path2D cases the model did not answer

`CHAIN.p2d.answer` only knew `GetLength` and the four curve queries, and built
the curve once at `SetControlPoints` time. Anything else came back as a miss,
which reads as a failed run rather than a number:

- **`GetBoundingRect`** had no case at all, though the caller above it already
  treated it as a curve query. It returns a `Rect2`, so `p2dEncode`/`p2dDecode`
  learned the `r:` kind.
- **The curve is now rebuilt on demand** (`M.refresh`), which covers points set
  before the Path2D is parented and a parent Frame resized afterwards - both
  used to make every later query a miss, because segments were only ever built
  when `SetControlPoints` ran.
- **A single control point** answers `GetLength` as 0 and still reports its
  box, instead of returning nil.

Verified by `deobf/research/p2d_check.py`: all 23 probed cases return real
numbers with zero miss markers, the out-of-range and negative curve parameters
clamp, and the bounding box correctly exceeds the frame when a handle reaches
past the last point (1.1 x the width on a 100px frame). The executor globals
added at the same time are covered by `deobf/research/exec_globals_check.py`.

## Tools (all runnable end to end, in `tools/`)

- `run_stage.luau` — run the extracted stage against the captured program
- `patch_stage.py` — inject `g6` / `GY` / `A[49]` logging into a copy
- `dump_g6.luau` — run the instrumented stage, call the program, dump TSVs
- `decode_stream.py` — align headers with the varint stream -> `stream.json`
- `parse_pool.py` / `derive_format.py` — pool decode and read-log validation
- `extract_a49.py` / `extract_funcs.py` — pull named functions out of the line
- `a49_dispatch.py` — dispatch tree -> `opcodes/<P>.lua` leaves
- `show_opcodes.py` / `dbg_fold.py <P>` — print leaves, show the P-test path
- `capture_program.luau` / `v14_stage.js` / `deob14.py` — extraction and driver

## Still open

- **The output is a behaviour trace, not a lift.** The trace is the readable
  answer and is what `/deob` returns, but it has only the branches that ran.
  Untaken branches and never-invoked callback bodies are absent. Folding it into
  the `simple.lua`/`lifted.lua` quality of the offline lifter is the obvious
  next step; the offline lifter itself is complete on two families.
- **`/deob` is wired to the v15 harness** (`deobfuscators/luraph_v14_deob.js`
  runs `deob.py --obfuscator luraph_v14 --no-devirt --debug` and returns the
  trace file). It is **one menu entry for the whole family**, not one per
  minor: splitting by minor only ever chose a label, and silently dropped
  v14.8 and v14.9, whose banner says `14.8` so neither "14.6" nor "14.7"
  matched. `detectLuraphV14` now takes the whole family, with the
  `V146_SHELL` / `V147_SHELL` / `INLINE_VM` shapes as extra evidence.
- **Four samples end in a spin-abort.** The user payload reaches an event-wait
  loop after building its GUI. To get the callback bodies, the fake environment
  has to fire the events it waits on (`mouse.Button1Click`, `TextButton.Activated`,
  frame signals) — the same problem ironbrew1's `Callback` double-run solves,
  applied to v14's spawn bodies.
- **Opcodes are not independent.** `K` is set by one opcode and consumed by
  later ones (161 is `K = d`, 65 assigns `K = i[G]`), so a lifter has to track it
  across a chain rather than fold each leaf alone.
- **The `+1` jump epilogue is universal** (stored target `N` executes at `N+1`)
  but its 14 canonical misses are unexplained; they are all P=94, the hottest
  opcode, so a wrong-but-popular target wins most rows.
- **Clone chains are not identified per dispatch** in s2, capping jump
  validation at a handful of transitions and leaving some operand reads
  ambiguous. It also recovers 12 statements against canonical's 390 on a
  comparable program — per-family statement coverage, not a naming problem.
- **Only the `(4)` program buffer is decoded offline.** `(2)`'s is recovered
  (`tools/work_s2/prog.bin`, 2,153,271 B) but not walked; the static-stage
  samples are detected and instrumented but have no automated buffer recovery,
  and `discover_anchors.py` covers the canonical dispatch shape only.
- **The two IEEE-754 values** (`4294967296` = 2^32, `4503599627370496` = 2^52)
  come from the step wrapper, whose slots hold encoded/tagged values rather than
  raw opcodes. That encoding is still unmapped — do not read them as opcodes.
- The envlogger's own dispatch patcher needs the same three fixes if it is ever
  used for v14 again: it had no v14 pattern (3,366 argument-less rows,
  histogram `?x3666`), `isL` never recognised a v14 stage so the patcher was
  skipped for exactly the input it was for, and the `==` pattern replaced only
  its first match. Prefer the v15 harness path, which is what ships.
- `env.spec` baseline 301 passed / 9 failed, unchanged throughout.
