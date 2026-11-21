import re

print("=== 1. math constants: does lifted math include e, tau, phi, sqrt2? ===")

print("fixture math order requires exact next() order including e, sqrt2, phi, tau")
print()

print("=== 2. What next() must yield for each lib ===")

print()
print("=== 3. debug additions needed ===")
print("dumpheap, loadmodule, setmetatable, getmemorycategory, validlevel, isvalidlevel, dumpcodesize, getmetatable (as key!), dumprefs")
print()
print("=== 4. script global ===")
print("fixture does script = { script = script } then walks it - needs global 'script' to exist")
