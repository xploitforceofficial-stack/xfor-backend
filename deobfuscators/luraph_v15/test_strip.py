"""strip_comments: only real comments go, strings keep every -- they hold."""
import sys

sys.path.insert(0, "deobf")
import traceout

FAIL = []

def ok(name, got, want):
    if got != want:
        FAIL.append(name)
        print("FAIL %s\n  got  %r\n  want %r" % (name, got, want))
    else:
        print("ok   %s" % name)

ok("url in string survives",
   traceout.strip_comments('local u = "https://x.com/a--b"\n'),
   'local u = "https://x.com/a--b"\n')

ok("comment after code goes",
   traceout.strip_comments('local a = 1 -- set a\n'),
   'local a = 1\n')

ok("escaped quote does not end the string",
   traceout.strip_comments('local s = "a\\"-- still string"\nlocal b = 2\n'),
   'local s = "a\\"-- still string"\nlocal b = 2\n')

ok("long string keeps its dashes",
   traceout.strip_comments('local p = [==[a -- b]==]\nlocal b = 2\n'),
   'local p = [==[a -- b]==]\nlocal b = 2\n')

ok("long-bracket comment goes",
   traceout.strip_comments('local a = 1\n--[[ gone\ngone ]]\nlocal b = 2\n'),
   'local a = 1\nlocal b = 2\n')

ok("comment inside a long string stays",
   traceout.strip_comments('local p = [==[ -- not a comment ]==]\n'),
   'local p = [==[ -- not a comment ]==]\n')

ok("nested-looking dashes in string",
   traceout.strip_comments('local s = [[a]] .. "--x" .. [[b]]\n'),
   'local s = [[a]] .. "--x" .. [[b]]\n')

ok("credit header kept",
   traceout.strip_comments("-- Deobfuscated by ccjvwsod on Discord\n"
                           "-- Detected obfuscation: Luraph v14\n"
                           "-- run status: finished\n"
                           "local a = 1\n"),
   "-- Deobfuscated by ccjvwsod on Discord\n"
   "-- Detected obfuscation: Luraph v14\n"
   "local a = 1\n")

ok("credit only counts at the top",
   traceout.strip_comments("local a = 1\n-- Deobfuscated by nobody\n"),
   "local a = 1\n")

ok("blank runs collapse",
   traceout.strip_comments("-- a\n-- b\n-- c\n\n\n\nlocal a = 1\n\n\n\nlocal b = 2\n"),
   "local a = 1\n\nlocal b = 2\n")

ok("chain markers go",
   traceout.strip_comments("--@1\nlocal a = 1\n--@2 3:inv\nlocal b = 2\n"),
   "local a = 1\nlocal b = 2\n")

ok("whole-line comment leaves no gap",
   traceout.strip_comments("local a = 1\n-- gone\nlocal b = 2\n"),
   "local a = 1\nlocal b = 2\n")

ok("trailing comment at EOF",
   traceout.strip_comments("local a = 1\n-- eof"),
   "local a = 1\n")

ok("unterminated long string does not hang",
   traceout.strip_comments('local s = [==[oops\n'),
   'local s = [==[oops\n')

ok("unicode survives",
   traceout.strip_comments('local s = "héllo -- wörld"\n-- gone\n'),
   'local s = "héllo -- wörld"\n')

print()
print("%d FAILURES" % len(FAIL) if FAIL else "all good")
raise SystemExit(1 if FAIL else 0)
