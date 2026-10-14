#!/usr/bin/env python3
"""Generate direct-HIR expectations only from pinned Rust smart constructors."""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--write-fixture', action='store_true')
parser.add_argument('--rust-only', action='store_true')
args = parser.parse_args()
# Rebuild the oracle from the checked-in pin and run the unchanged upstream tests.
subprocess.run(['python3', 'scripts/check_thompson_syntax_adoption.py', '--rust-only'], check=True)
# Characterizations of Hir::alternation, singleton_chars/bytes and c_alt_slice.
# '-' means no alternatives; '_' means an empty literal. Hex permits invalid UTF-8.
cases = [('-', 'empty'), ('_', 'singleton_empty'), ('61', 'singleton_ascii'),
         ('e29883', 'singleton_unicode'), ('ff', 'singleton_invalid'),
         ('61,62', 'ascii'), ('63,61,62,61', 'unordered_ascii'), ('61,61', 'duplicate_ascii'),
         ('ceb1,ceb2', 'unicode'), ('ceb2,ceb1,ceb2', 'unordered_unicode'),
         ('e29883,e29883', 'duplicate_unicode'), ('f09f918d,f09f918e', 'four_byte'),
         ('f09f918d,f09f918d', 'duplicate_four_byte'), ('ed9fbf,ee8080', 'surrogate_boundary'),
         ('00,7f', 'ascii_boundary'), ('fe,ff', 'invalid_bytes'), ('ff,ff', 'duplicate_invalid'),
         ('61,ff', 'mixed_bytes'), ('ceb1,ff', 'mixed_unicode_byte'),
         ('c0af,c0ae', 'invalid_sequences'), ('6162,6364', 'literal_trie'),
         ('_,61', 'empty_first'), ('61,_', 'empty_last')]
rows = []
for encoded, name in cases:
    for captures in ['none', 'all']:
        for reverse in [0, 1]:
            # Rust rejects explicit captures in reverse compilation.
            if captures == "all" and reverse:
                continue
            for shrink in [0, 1]:
                rows.append(f'direct_hir_{name}\t{captures},0,{reverse},{shrink},0,0\t{encoded}')
inputs = '\n'.join(rows) + '\n'
oracle = ROOT / 'temp/thompson-syntax-adoption/rust-oracle'
graphs = subprocess.check_output([str(oracle)], input=inputs, text=True).splitlines()
assert len(graphs) == len(rows)
fixture = '# Rust 72d650cb0a880a01ab6dc2137c0888e8f89740f7 Hir::alternation and Thompson c_alt_slice\n'
fixture += '# native_characterization\tconfiguration\tliteral_bytes_hex\texact_graph\n'
fixture += '\n'.join(row + '\t' + graph for row, graph in zip(rows, graphs)) + '\n'
path = ROOT / 'spec/fixtures/direct_hir_alternation.tsv'
if args.write_fixture:
    path.write_text(fixture)
else:
    assert path.read_text() == fixture, 'Direct HIR fixture differs from pinned Rust'
print(f'{len(rows)} direct-HIR native graph characterizations')
if not args.rust_only:
    env = dict(os.environ, TMPDIR=str(ROOT / 'temp'), CRYSTAL_CACHE_DIR=str(ROOT / 'temp/crystal-cache'))
    env.pop('CRYSTAL_PATH', None)
    subprocess.run(['crystal', 'spec', 'spec/direct_hir_alternation_spec.cr'], env=env, check=True)
