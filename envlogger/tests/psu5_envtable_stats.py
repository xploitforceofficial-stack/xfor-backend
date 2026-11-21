"""Classify PSU v5 env-table entries: char bindings, single chars, numbers, long strings."""
import json

e = json.load(open('Samples/PSU/v5/_envtable.json', encoding='utf-8'))
nums = {}
chars = {}
words = {}
for k, v in e.items():
    try:
        fk = int(k)
    except ValueError:
        continue
    try:
        fv = float(v)
        is_num = True
    except (TypeError, ValueError):
        is_num = False
    if is_num:
        nums[fk] = fv
    elif len(str(v)) == 1:
        chars[fk] = v
    else:
        words[fk] = v

print("numbers:", len(nums), " single-chars:", len(chars), " words:", len(words))
print("\nsingle-char bindings (likely name decryption keys):")
for k in sorted(chars):
    print(" ", k, "->", repr(chars[k]))
print("\nwords:")
for k in sorted(words):
    print(" ", k, "->", repr(words[k]))
print("\nfirst 20 numbers:")
for k in sorted(nums)[:20]:
    print(" ", k, "->", nums[k])
