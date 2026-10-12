#!/usr/bin/env python3
"""Compare exact Thompson graphs through the normally installed syntax shard.

Expected data is generated only by the pinned Rust source. No CRYSTAL_PATH or
path overrides select a different Crystal dependency. Scratch lives in temp/.
"""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--write-fixture', action='store_true')
parser.add_argument('--rust-only', action='store_true')
args = parser.parse_args()
source = ROOT / 'vendor/regex'
pin = '72d650cb0a880a01ab6dc2137c0888e8f89740f7'
assert subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip() == pin
temp = ROOT / 'temp/thompson-syntax-adoption'
temp.mkdir(parents=True, exist_ok=True)
rows = []
def case(name, pattern, captures='none', prefix=False, reverse=False, shrink=False, syntax_utf8=True, nfa_utf8=True):
    patterns = pattern if isinstance(pattern, list) else [pattern]
    config = ','.join([captures, *[str(int(v)) for v in [prefix, reverse, shrink, syntax_utf8, nfa_utf8]]])
    rows.append('\t'.join([name, config, ','.join(p.encode().hex() for p in patterns)]))

case('compile_unanchored_prefix', 'a', prefix=True)
case('compile_no_unanchored_prefix_with_start_anchor', '^a', prefix=True)
case('compile_yes_unanchored_prefix_with_end_anchor', 'a$', prefix=True)
case('compile_yes_reverse_unanchored_prefix_with_start_anchor', '^a', prefix=True, reverse=True)
case('compile_no_reverse_unanchored_prefix_with_end_anchor', 'a$', prefix=True, reverse=True)
case('compile_empty', '')
for p in ['a', 'ab', '☃']:
    case('compile_literal', p)
case('compile_literal', r'(?-u)\xFF', syntax_utf8=False)
for p in ['[a-z]', '[x-za-c]']:
    case('compile_class_ascii', p)
for p in [r'[\u03B1-\u03B4]', r'[\u03B1-\u03B4\u{1F919}-\u{1F91E}]', '[a-z☃]']:
    case('compile_class_unicode', p)
for p in ['a?', 'a??']:
    case('compile_repetition', p)
for p in ['ab+', '(ab)', '(ab)+']:
    case('compile_group', p)
for p in ['a|b', 'ab|cd', '|b', 'a|']:
    case('compile_alternation', p)
case('compile_non_binary_union', r'[\u1000\u2000\u3000]', reverse=True)
case('compile_many_start_pattern', ['a', 'b'])
case('empty_class_bytes', '')
case('empty_class_unicode', '')
for policy in ['all', 'implicit', 'none']:
    case('compile_captures_' + policy, 'a(b)c', captures=policy)
original_rows = len(rows)
assert original_rows == 31
# Native characterizations beyond the original compiler tests: normalization
# and combinations most likely to expose stale syntax dependencies.
patterns = ['a|b', 'ab|ac', '[a-c]|[d-f]', 'a|[b-d]', 'foo|foobar|fooz',
            'a|a', '|a|b', 'α|β', 'αβ|αγ', '[a-z☃]', r'[\uD7FF-\uE001]',
            '(?i:a|b)', 'a{2,5}', '(?:a?)*', 'a?|b+|c*d', '(?m:^a$)',
            r'\bword\b', r'(?-u:\xFE|\xFF)']
for p in patterns:
    for reverse in [False, True]:
        for shrink in [False, True]:
            case('syntax_normalization', p, reverse=reverse, shrink=shrink, syntax_utf8=False)
# All 18 supported look assertions, also in reverse and shrink modes.
looks = [r'\A', r'\z', r'(?m:^)', r'(?m:$)', r'(?mR:^)', r'(?mR:$)',
         r'(?-u:\b)', r'(?-u:\B)', r'\b', r'\B']
for suffix in ['start', 'end', 'start-half', 'end-half']:
    looks.extend([r'\b{' + suffix + '}', r'(?-u:\b{' + suffix + '})'])
for p in looks:
    for reverse in [False, True]:
        for shrink in [False, True]:
            case('look_contract', p, reverse=reverse, shrink=shrink)
for p in ['(?P<outer>a(?P<inner>b|c))?', '(a|b)+(c*)']:
    for policy in ['all', 'implicit', 'none']:
        for prefix in [False, True]:
            case('capture_normalization', p, captures=policy, prefix=prefix)
case('raw_byte_mode', r'(?-u:\xFE|\xFF)', syntax_utf8=False, nfa_utf8=False)
inputs = '\n'.join(rows) + '\n'
(temp / 'inputs.tsv').write_text(inputs)
features = ['std', 'unicode', 'unicode-age', 'unicode-bool', 'unicode-case',
            'unicode-gencat', 'unicode-perl', 'unicode-script', 'unicode-segment']
cfg = [arg for f in features for arg in ['--cfg', f'feature="{f}"']]
syntax = temp / 'libregex_syntax.rlib'
subprocess.run(['rustc', '--edition=2021', '--crate-type=rlib', '--crate-name=regex_syntax',
                str(source / 'regex-syntax/src/lib.rs'), '-o', str(syntax), *cfg], check=True)
# Run the original compiler unit tests without Cargo dev-dependency downloads.
# Only unrelated test modules are disabled; compiler assertions stay unchanged.
copy = temp / 'automata-src'
if copy.exists():
    shutil.rmtree(copy)
shutil.copytree(source / 'regex-automata/src', copy)
for path in copy.rglob('*.rs'):
    if path.name.startswith('._') or path.relative_to(copy).as_posix() == 'nfa/thompson/compiler.rs':
        continue
    original = path.read_text()
    original = re.sub(r'#\[cfg\((.*?)\)\]', lambda m: '#[cfg(' + re.sub(r'\btest\b', 'any()', m[1]) + ')]', original, flags=re.S)
    path.write_text(original)
automata = temp / 'libregex_automata.rlib'
auto_cfg = [arg for f in ['std', 'alloc', 'syntax', 'nfa-thompson', 'unicode-word-boundary'] for arg in ['--cfg', f'feature="{f}"']]
tests = temp / 'rust-compiler-tests'
subprocess.run(['rustc', '--edition=2021', '--test', '--crate-name=regex_automata',
                str(copy / 'lib.rs'), '--extern', f'regex_syntax={syntax}', '-o', str(tests), *auto_cfg], check=True)
listing = subprocess.check_output([str(tests), '--list'], text=True)
assert sum(line.endswith(': test') for line in listing.splitlines()) == 19
subprocess.run([str(tests), 'nfa::thompson::compiler::tests::', '--test-threads=1'], check=True)
# Rust's unanchored_prefix setter is available only to its in-crate tests.
# Expose the same option in the disposable oracle copy, never in vendor.
compiler_source = copy / 'nfa/thompson/compiler.rs'
text = compiler_source.read_text()
start = text.index('#[cfg(test)]\nmod tests')
head = text[:start].replace('#[cfg(test)]', '').replace('fn unanchored_prefix(', 'pub fn unanchored_prefix(')
getter_start = head.index('    fn get_unanchored_prefix(&self) -> bool {')
getter_end = head.index('    /// Overwrite the default configuration', getter_start)
head = head[:getter_start] + '    fn get_unanchored_prefix(&self) -> bool { self.unanchored_prefix.unwrap_or(true) }\n\n' + head[getter_end:]
compiler_source.write_text(head + text[start:])
subprocess.run(['rustc', '--edition=2021', '--crate-type=rlib', '--crate-name=regex_automata',
                str(copy / 'lib.rs'), '--extern', f'regex_syntax={syntax}',
                '-o', str(automata), *auto_cfg], check=True)
oracle = temp / 'rust-oracle'
subprocess.run(['rustc', '--edition=2021', 'scripts/parity/thompson_graph.rs',
                '--extern', f'regex_syntax={syntax}', '--extern', f'regex_automata={automata}',
                '-L', str(temp), '-o', str(oracle)], check=True)
expected = subprocess.check_output([str(oracle)], input=inputs, text=True).splitlines()
assert len(expected) == len(rows)
fixture = '# Pinned Rust Thompson compiler; revision ' + pin + '\n'
fixture += '# test_or_characterization\tcaptures,prefix,reverse,shrink,syntax_utf8,nfa_utf8\tpatterns_hex\texact_graph\n'
fixture += '\n'.join(row + '\t' + graph for row, graph in zip(rows, expected)) + '\n'
# Account for every original compiler assertion; metadata assertions are part
# of the same exact snapshot as their state array.
text = (source / 'regex-automata/src/nfa/thompson/compiler.rs').read_text()
start = text.index('#[cfg(test)]\nmod tests')
ledger = ['# source_assertion\tcrystal_evidence\tnative_case\tnotes']
for number, line in enumerate(text.splitlines(), 1):
    if number <= text[:start].count('\n') or not re.search(r'\bassert(?:_eq|_ne)?!\(', line):
        continue
    test = list(re.finditer(r'fn (\w+)\(', '\n'.join(text.splitlines()[:number])))[-1][1]
    assert any(row.startswith(test + '\t') for row in rows[:original_rows]), test
    ledger.append(f'src/nfa/thompson/compiler.rs:{number}\tspec/thompson_syntax_adoption_spec.cr\t{test}\tExact native states, order, edges, start states, capture slots and group count; original upstream assertion retained in native compiler tests')
assert len(ledger) - 1 == 38
for path, content in [(ROOT / 'spec/fixtures/thompson_syntax_adoption.tsv', fixture),
                      (ROOT / 'plans/inventory/rust_thompson_compiler_assertion_audit.tsv', '\n'.join(ledger) + '\n')]:
    if args.write_fixture:
        path.write_text(content)
    elif path.read_text() != content:
        raise SystemExit(f'{path.name} differs from the pinned Rust oracle')
print(f'{original_rows} original compiler graph cases; {len(ledger)-1} assertion locations; {len(rows)-original_rows} native characterizations')
if not args.rust_only:
    env = dict(os.environ, CRYSTAL_CACHE_DIR=str(ROOT / 'temp/crystal-cache'), TMPDIR=str(ROOT / 'temp'))
    env.pop('CRYSTAL_PATH', None)
    subprocess.run(['crystal', 'spec', 'spec/thompson_syntax_adoption_spec.cr'], env=env, check=True)
