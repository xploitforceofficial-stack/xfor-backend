"""
luraph_v14: Luraph v14.6 / v14.7.

v14 is not a bytecode-lifting target the way v15 is. Its outer loader decrypts a
*stage*, and that stage is the VM runtime - a table of closures that interprets
the real program one dispatch step at a time. The user's code never appears in
the file as bytecode, so there is nothing to lift directly; the work is to read
the interpreter and say what it does.

What this plugin does, in order:

  1. run the script in the shared Luau harness against the fake Roblox
     environment, which is what makes the loader decrypt the stage
  2. instrument that stage's loop heads with the __SPIN step counter
     (`scope.inject_spin_all`) and run it again, so the v14 VM - a pure
     endless loop of arithmetic as far as the tracer is concerned - still
     reports what the user's code did before it settled into a wait loop
  3. read the stage's dispatch tables with isa.build_isa - every `if X==tag`
     chain, its state slot, each tag's body and the tags it transitions to

Step 2 needs the stage before the run can start, and v14 has three loader
shapes: zstd blobs decoded on the host (`zblobs`), a stage shipped as the file
itself (v14.7 base, v14.8), and an LZ loader that `loadstring`s it - for that
last one the first run is a capture pass and the stage comes from the chunks
the sandbox reported (which is why `envlog.luau` reports a chunk the moment it
appears rather than at the end: a spin kills the run before the end).

The readable output is the behaviour trace (`<name>.deobf.luau`); the stage
plus its dispatch tables go to `<name>.luau`. Notes: LURAPH14.md.

Still open: the trace has only the branches that ran, and the four samples
whose payload ends in an event-wait have no callback bodies.
"""
import os
import re
import sys
import time

import backend
import harness
import luauast
import traceout as trace
from obfuscators.base import Obfuscator
from obfuscators.luraph_v14 import isa
from obfuscators.luraph_v14 import scope
from obfuscators.luraph_v14 import zblobs
from obfuscators.luraph_v14 import envfill

HERE = os.path.dirname(os.path.abspath(__file__))

BANNER = re.compile(r"Luraph\s+Obfuscator\s+v14", re.I)

CLOSURE_TABLE = re.compile(r"return\s*\(\s*\{[A-Za-z_]\w*\s*=\s*function")

STEP_WRAPPER = re.compile(
    r"repeat\s+[A-Za-z_]\w*\s*,\s*[A-Za-z_]\w*\s*,\s*[A-Za-z_]\w*\s*,\s*[A-Za-z_]\w*\s*="
    r"\s*[A-Za-z_]\w*\s*:\s*[A-Za-z_]\w*\s*\(")

STAGE_RE = re.compile(r"\x00STAGE (\d+) ([^\n]*)")

INLINE_STAGE = re.compile(
    r"^\s*(--[^\n]*\n)*\s*return\s*\(\s*\{\s*[A-Za-z_]\w*\s*=\s*function")

class LuraphV14(Obfuscator):
    name = "luraph_v14"
    label = "Luraph v14"

    def detect(self, source):
        head = source[:4000]
        if BANNER.search(head):
            return 0.95
        if CLOSURE_TABLE.search(head) and STEP_WRAPPER.search(source):
            return 0.8
        if CLOSURE_TABLE.search(head) and "until false" in source:
            return 0.6
        return 0.0

    def add_arguments(self, parser):
        pass

    def _run(self, job, source, cfg, chunks=None):
        runner = harness.Runner(job)
        cfg = harness.user_cfg(job.args, cfg)
        print("[*] tracing %s..." % job.input, file=sys.stderr)
        t0 = time.time()
        try:
            blobs = zblobs.build_map(source)
        except Exception as e:
            print("[!] v14 blob pre-decode failed (%s: %s); loader runs without it"
                  % (type(e).__name__, e), file=sys.stderr)
            blobs = None
        if blobs:
            chunks = self._stage_chunks(sorted(
                (v.decode("latin-1") if isinstance(v, bytes) else v)
                for v in blobs.values()))
        if chunks is None and INLINE_STAGE.search(source):

            patched, nheads = scope.inject_spin_all(source, conditional=True,
                                                   repeats=True)
            if nheads:
                print("[*] v14 inline stage: %d loop head(s) instrumented"
                      % nheads, file=sys.stderr)
                return self._trace(runner, job, patched, cfg, blobs)
        if chunks is None:

            body, err = runner.run(source, cfg, None, zblobs=blobs or None)
            found, _ = harness.take_chunks(harness.LAST_RAW[0])
            chunks = self._stage_chunks([src for _k, src in found])
            if not chunks:
                if body is None:
                    print("[!] the harness could not run it: %s" % err, file=sys.stderr)
                    return None
                return body
            print("[*] v14 stage captured from the loader, re-running instrumented",
                  file=sys.stderr)
        return self._trace(runner, job, source, cfg, blobs, chunks)

    def _trace(self, runner, job, source, cfg, blobs, chunks=None):
        """The instrumented run, plus the loader/blobs it needs."""
        t0 = time.time()
        body, err = runner.run(source, cfg, chunks, zblobs=blobs or None)
        runner.finish()
        harness.save_raw(job.args.raw)
        if body is None:
            print("[!] the harness could not run it: %s" % err, file=sys.stderr)
            return None
        print("[*] run: %.1fs" % (time.time() - t0), file=sys.stderr)
        return body

    def _stage_chunks(self, sources):
        """{chunk_key: spin-patched stage} so the loader runs our stage copy.

        The stage is the smallest candidate that parses as Luau (the program
        blob is binary, and the loadstring'd payloads that follow the stage are
        the user's own code, which must run untouched). Its dispatch heads get
        the __SPIN step counter (see scope.inject_spin) reusing the runtime that
        already exists when CFG.spin is set - this is what keeps a long pure-VM
        run visible (heartbeats) and terminates a real spin with the trace so
        far. None when there is nothing to do.
        """
        stage = None
        for txt in sources:
            try:
                luauast.parse(txt)
            except Exception:
                continue
            stage = txt
            break
        if stage is None:
            return None

        key = harness.chunk_key(stage)
        try:
            filled_stage, nfilled = envfill.backfill(stage)
            luauast.parse(filled_stage)
            stage = filled_stage
        except Exception as e:
            print("[!] v14 env backfill skipped (%s: %s)" % (type(e).__name__, e),
                  file=sys.stderr)
            nfilled = 0

        patched, nheads = scope.inject_spin_all(stage, conditional=True,
                                               repeats=True)
        if not nheads:
            print("[!] v14 second pass: no loops in stage; unpatched",
                  file=sys.stderr)
            return None
        print("[*] v14 second pass: stage %d bytes, env backfill %d, %d loop head(s), chunk %s"
              % (len(stage), nfilled, nheads, key), file=sys.stderr)
        return {key: patched}

    def _stage_from(self, body):
        """The decrypted stage, if the sandbox handed one back."""
        if not body:
            return None
        m = STAGE_RE.search(body)
        if not m:
            return None
        return m.group(2).encode("latin-1").decode("latin-1")

    def deobfuscate(self, job):
        source = job.source
        cfg = harness.base_cfg(job.args)

        cfg.setdefault("spin", 30)

        body = self._run(job, source, cfg)
        stage = self._stage_from(body) or source
        ran = body is not None

        tables = isa.build_isa(stage)
        instrumented, loops = stage, []
        if not job.args.no_devirt:
            try:
                instrumented, loops = backend.run_big_stack(scope.inject, stage)
            except Exception as e:
                print("[!] could not instrument the stage (%s: %s); tables only"
                      % (type(e).__name__, e), file=sys.stderr)
                instrumented, loops = stage, []

        out = [job.credit_header()]
        m = BANNER.search(source[:4000])
        if m:
            out.append("-- banner: %s\n" % m.group(0))
        out.append("-- stage recovered from a sandbox run: %s\n" % ("yes" if ran else "no"))
        out.append("-- dispatch chains: %d   instrumented loops: %d\n"
                   % (len(tables.get("interpreters") or []), len(loops)))
        if tables.get("step_wrapper"):
            out.append("-- step wrapper: repeat a,b,c,d=x:y(...) until false  (-2 = halt)\n")
        table = isa.render_isa(tables)
        if table:
            out.append(table)
        if loops:
            out.append("-- instrumented dispatch loops (state / tags / operands):\n")
            for i in loops:
                out.append("--   %-6s %-24s %s\n"
                           % (i["state"], str(i["tags"][:4]), i["operands"]))
            out.append("--\n")
        out.append("-- ---- decrypted stage ----\n")
        out.append(instrumented)

        path = job.write(job.path(".luau"), "".join(out))

        if ran and body:
            cache_path = harness.load_p2d_cache(job.input, job.args.studio)
            tbody = harness.take_p2d(body, cache_path, job.args.studio)
            tbody = harness.p2d_miss(tbody, cache_path)
            _, tbody = harness.take_chunks(tbody)
            tbody = re.sub(r"\x00STAGE \d+ [^\n]*\n?", "", tbody)
            tbody, strings = trace.take_strings(tbody)
            job.write(job.trace_path,
                      trace.render(trace.header(job.input) + tbody, job.args, preamble=False))
            if strings is not None:
                job.write(job.path(".strings.txt"), strings)
            trace.status_line(tbody)

            mstat = re.search(r"-- run status: (.+)", tbody)
            print("[*] v14 trace: %d statement(s), %d chain(s), status: %s"
                  % (trace.stmt_count(tbody), len(tables.get("interpreters") or []),
                     mstat.group(1).strip() if mstat else "unknown"),
                  file=sys.stderr)

        print("[*] %d dispatch chain(s), %d instrumented loop(s), stage from run: %s"
              % (len(tables.get("interpreters") or []), len(loops), "yes" if ran else "no"),
              file=sys.stderr)
        return path

    def _stage_from(self, body):
        """The decrypted stage, if the sandbox handed one back."""
        if not body:
            return None
        m = STAGE_RE.search(body)
        if not m:
            return None
        return m.group(2).encode("latin-1").decode("latin-1")
