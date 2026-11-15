"""Keep cold samples visible in raw files; summarize warm independent repeats."""
import statistics
import sys
from pathlib import Path
root = Path(sys.argv[1])
results = {}
for implementation in ['baseline', 'current', 'scalar', 'rust']:
    rows = {}
    for run in range(1, 4):
        for line in (root / f'{implementation}-{run}.tsv').read_text().splitlines():
            name, sample, iterations, nanos, allocated, probes, checksum = line.split('\t')
            if int(sample) == 0:
                continue
            times, allocations = rows.setdefault(name, ([], []))
            times.append(int(nanos) / int(iterations))
            if allocated != '-':
                allocations.append(int(allocated) / int(probes))
    results[implementation] = rows
print('Phase 8 release measurements; baseline `8edddc8`, current checkout and pinned Rust.')
print('Three process runs, first sample per workload discarded; warm mean ns/op and range retained.')
print('Crystal allocation columns are GC-tracked bytes/op from separate 16-operation probes; no Rust allocator equivalence is asserted.\n')
print('| Workload | Baseline ns/op | Current ns/op (range) | Scalar DFA ns/op | Rust ns/op | Current/baseline | GC bytes baseline/current |')
print('|---|---:|---:|---:|---:|---:|---:|')
for name in results['current']:
    b, ba = results['baseline'][name]
    c, ca = results['current'][name]
    r, _ = results['rust'][name]
    u, _ = results['scalar'][name]
    bm, cm, rm = map(statistics.mean, (b, c, r))
    print(f'| {name} | {bm:.1f} | {cm:.1f} ({min(c):.1f}–{max(c):.1f}) | {statistics.mean(u):.1f} | {rm:.1f} | {cm/bm:.3f} | {statistics.mean(ba):.1f}/{statistics.mean(ca):.1f} |')
