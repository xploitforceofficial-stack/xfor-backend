"""Path2D model: every method a script can call must answer, not miss.

Three cases used to come back as a miss instead of a number, which reads as a
failed run:
  - GetBoundingRect had no case at all, though the caller above it already
    treated it as a curve query;
  - a curve set before the Path2D is parented, or whose parent Frame is resized
    afterwards, because segments were only ever built at SetControlPoints time;
  - a single control point (no segment to be on).

print is traced, so a probe that prints turns into an expression; warn is traced
too but renders its arguments, so warn("KEY", value) puts the number into the
trace text where this script can read it back. Proxy results are checked through
their numeric components, which also proves the model returned real numbers
rather than staying symbolic.

Usage: python deobf/research/p2d_check.py
"""
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import harness

PROBE = r"""
local function w(k, v) warn("P2DPROBE", k, v) end
local function udim2(k, u)
	w(k .. ".X.Scale", u.X.Scale) w(k .. ".X.Offset", u.X.Offset)
	w(k .. ".Y.Scale", u.Y.Scale) w(k .. ".Y.Offset", u.Y.Offset)
end
local function vec2(k, v)
	w(k .. ".X", v.X) w(k .. ".Y", v.Y)
end
local F = Instance.new("Frame")
F.Size = UDim2.new(0, 100, 0, 50)
local P = Instance.new("Path2D")
P.Parent = F
P:SetControlPoints({
  Path2DControlPoint.new(UDim2.new(0,0,0,0), UDim2.new(0,0,0,0), UDim2.new(0,10,0,0)),
  Path2DControlPoint.new(UDim2.new(1,0,1,0), UDim2.new(0,10,0,0), UDim2.new(0,-10,0,0)),
})
w("len", P:GetLength())
udim2("pos", P:GetPositionOnCurve(0.5))
vec2("tan", P:GetTangentOnCurve(0.5))
udim2("posArc", P:GetPositionOnCurveArcLength(0.5))
udim2("overRange", P:GetPositionOnCurve(5))
udim2("negative", P:GetPositionOnCurve(-3))
udim2("end", P:GetPositionOnCurve(1))
local b = P:GetBoundingRect()
vec2("boundsMin", b.Min) vec2("boundsSize", b.Size)
w("maxPts", P:GetMaxControlPoints())
w("nPts", #P:GetControlPoints())

-- points set BEFORE parenting: used to answer nothing at all
local Q = Instance.new("Path2D")
Q:SetControlPoints({
  Path2DControlPoint.new(UDim2.new(0,0,0,0)),
  Path2DControlPoint.new(UDim2.new(1,0,1,0)),
})
Q.Parent = F
w("lateLen", Q:GetLength())

-- parent resized after the points were set: the curve is in pixels, so the
-- length has to change
F.Size = UDim2.new(0, 200, 0, 100)
w("afterResizeLen", P:GetLength())
F.Size = UDim2.new(0, 100, 0, 50)

-- one control point: no segment, but the box is still known
local R = Instance.new("Path2D")
R.Parent = F
R:SetControlPoints({ Path2DControlPoint.new(UDim2.new(0.5,0,0.5,0)) })
w("singleLen", R:GetLength())
vec2("singleMin", R:GetBoundingRect().Min)
vec2("singleSize", R:GetBoundingRect().Size)
"""

EXPECT = ["len", "maxPts", "nPts", "lateLen", "afterResizeLen", "singleLen",
          "pos.X.Scale", "pos.X.Offset", "pos.Y.Scale", "pos.Y.Offset",
          "tan.X", "tan.Y", "posArc.X.Scale", "posArc.Y.Offset",
          "overRange.Y.Scale", "negative.Y.Scale", "end.Y.Scale",
          "boundsMin.X", "boundsMin.Y", "boundsSize.X", "boundsSize.Y",
          "singleMin.X", "singleSize.X"]

VALUES = {
    "maxPts": "100",
    "nPts": "2",
    "singleLen": "0",

    "overRange.Y.Scale": "1",
    "negative.Y.Scale": "0",
    "end.Y.Scale": "1",

    "boundsSize.X": "1.1000000238418579",
}

def main():
    hpath = os.path.join(tempfile.gettempdir(), "p2d_check.harness.luau")
    body, err = harness.run_once(harness.find_luau(), PROBE, {"time_budget": 30},
                                 hpath, 90, False)
    raw = harness.LAST_RAW[0]
    if body is None:
        print("NO BODY:", (err or "")[:600])
        print(raw[-1200:])
        return 1
    found = {}
    for m in re.finditer(r'warn\("P2DPROBE",\s*"([^"]+)",\s*([-\d.eE+]+|nil)\)', raw):
        found.setdefault(m.group(1), m.group(2))

    bad = []
    for k in EXPECT:
        got = found.get(k)
        want = VALUES.get(k)
        ok = got is not None and (want is None or got == want)
        if not ok:
            bad.append(k)
        print("%-20s %-24s %s" % (k, got, "ok" if ok else "WANT " + str(want)))
    misses = raw.count("P2DMISS")
    print()
    print("%d unanswered, %d Path2D miss markers" % (len(bad), misses))
    if bad:
        print("unanswered: %s" % bad)
    return 1 if (bad or misses) else 0

if __name__ == "__main__":
    raise SystemExit(main())
