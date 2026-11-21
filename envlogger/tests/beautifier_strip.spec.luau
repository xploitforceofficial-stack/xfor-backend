local Beautifier = require("../src/analysis/beautifier")

local passed = 0
local failed = 0

local function check(name, got, expected)
    if got == expected then
        passed += 1
    else
        failed += 1
        print("FAIL: " .. name)
        print("  expected: " .. expected)
        print("  got:      " .. got)
    end
end

check("param type", Beautifier.stripLuauSyntax("local x: number = 5"), "local x = 5")
check("func params", Beautifier.stripLuauSyntax("local function foo(x: string, y: number?): string"), "local function foo(x, y)")
check("func return", Beautifier.stripLuauSyntax("function bar(a: Instance): boolean"), "function bar(a)")

check("local generic", Beautifier.stripLuauSyntax("local x<T> = {}"), "local x = {}")
check("func generic", Beautifier.stripLuauSyntax("function foo<T>(x: T)"), "function foo(x)")

check("type cast", Beautifier.stripLuauSyntax("local x = y :: string"), "local x = y")
check("cast in expr", Beautifier.stripLuauSyntax("local x = (y :: any).foo"), "local x = (y).foo")

check("typed vararg", Beautifier.stripLuauSyntax("function foo(...: any)"), "function foo(...)")

check("nolint comment", Beautifier.stripLuauSyntax("--!nolint\nlocal x = 5"), "\nlocal x = 5")
check("nonstrict comment", Beautifier.stripLuauSyntax("--!nonstrict\nlocal x = 5"), "\nlocal x = 5")

check("export type", Beautifier.stripLuauSyntax("export type Foo = { bar: string }"), "-- export type Foo = { bar: string }")

check("BOM removal", Beautifier.stripLuauSyntax("\239\187\191local x = 5"), "local x = 5")

check("plain lua", Beautifier.stripLuauSyntax("local x = 5"), "local x = 5")
check("binary literal", Beautifier.stripLuauSyntax("local x = 0b1010"), "local x = 0b1010")

print(string.format("beautifier.stripLuauSyntax: %d passed, %d failed", passed, failed))
