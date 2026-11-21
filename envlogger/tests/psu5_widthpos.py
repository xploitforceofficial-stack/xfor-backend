"""Statistical: if [width][value] varint, the char AT each code start should have
small IDX (1..4) mostly. Walk assuming the stream restarts: try every width alphabet
mapping f(ch) in {1..4} that makes the stream self-consistent (lengths add up to 500000,
no overlaps). Search: width = IDX[ch] % 5? Or widths derived from value digits?
Better: examine positions of chars in the first 200 bytes IF width==2 everywhere:
then 250000 codes. width==3: 166666 codes. What distribution of IDX at 3k+0?"""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
blob = s[439:439+500000]
A62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
IDX = {c: i for i, c in enumerate(A62)}

for w in (1, 2, 3, 4):
    starts = range(0, 2000, w + 1)
    idxs = [IDX[blob[i]] for i in starts]
    frac_small = sum(1 for v in idxs if v <= 4) / len(idxs)
    print(f'uniform width {w}: frac(width_char IDX<=4) = {frac_small:.3f}')
