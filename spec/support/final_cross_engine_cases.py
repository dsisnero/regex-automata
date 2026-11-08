"""Bounded deterministic adversarial families; expected results come from Rust."""
import sys
families = [
    (["(a+)(b?)"], [b"aaab", b"zab!", b""], True, 10),
    (["(ab|a)+"], [b"aba", b"aaab", b"b"], True, 10),
    (["a", "ab", "abc"], [b"abc", b"zab", b""], True, 10),
    ([r"(?-u:\b)[a-z]+(?-u:\b)"], [b"!abc!", b"a1", b"\xffa"], True, 10),
    ([r"\b[a-z]+\b"], ["é abc".encode(), b"!abc!", b"\xffa"], True, 10),
    (["é+"], ["éé!".encode(), "xé".encode(), b""], True, 10),
    (["😀+"], ["x😀😀!".encode(), b"x", b""], True, 10),
    ([r"(?-u:\xFF+)"], [b"\xff\xff!", b"a\xff", b""], False, 10),
    ([r"(?-u:.)?"], [b"\x00\xff", b"a\n", b""], False, 10),
    (["a*"], [b"bbb", b"aaa", "é".encode()], True, 10),
    (["^a+$"], [b"aaa", b"baaa", b""], True, 10),
    (["a+$"], [b"zaaa", b"aab", b""], True, 10),
    (["(?m)^a+$"], [b"x\naaa\nx", b"aaa\n", b""], True, 10),
    (["((a)|(b))+"], [b"abba", b"za", b""], True, 10),
    (["(?:a|aab)c"], [b"aabc", b"aac", b"ac"], True, 10),
    (["(?P<word>[a-z]+)(?P<n>[0-9]*)"], [b"abc123", b"!z", b""], True, 10),
    (["(?i:.)", "(.)"], [b"X", b"\n", b"aXb"], True, 88),
    (["(abc)+"], [b"abcabcabc", b"abc!", b""], True, 10),
    (["("], [b""], True, 10),
    (["[z-a]"], [b""], True, 10),
]
count = 0
for family, (patterns, haystacks, utf8, terminator) in enumerate(families):
    for h, hay in enumerate(haystacks):
        n = len(hay)
        bounds = list(dict.fromkeys([(0, n), (0, 0), (n, n), (min(1, n), n), (n + 1, n)]))
        for b, (start, end) in enumerate(bounds):
            for anchor in ["no", "yes", "p0", "p1"]:
                for earliest in [0, 1]:
                    # Both match kinds exercise rejection/admission as well as results.
                    kind = "all" if (family + h + b + earliest) % 5 == 0 else "first"
                    fields = [f"g{family:02}-{h}-{b}-{anchor}-{earliest}",
                              ",".join(p.encode().hex() for p in patterns), hay.hex(),
                              str(start), str(end), anchor, str(earliest), str(int(utf8)),
                              str(terminator), kind]
                    print("\t".join(fields))
                    count += 1
print(f"generated {count} bounded cases", file=sys.stderr)
