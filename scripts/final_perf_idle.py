"""Refuse timing unless the Linux runner is mostly idle (including steal)."""
import sys
import time
from pathlib import Path
if sys.platform != "linux":
    raise SystemExit("Controlled timing is restricted to the Linux CI runner; use check locally")
def cpu():
    fields = [int(x) for x in Path('/proc/stat').read_text().splitlines()[0].split()[1:9]]
    return sum(fields), fields[3]  # iowait/steal are deliberately not idle
consecutive = 0
for attempt in range(20):
    before, idle_before = cpu()
    time.sleep(1)
    after, idle_after = cpu()
    fraction = (idle_after - idle_before) / max(1, after - before)
    consecutive = consecutive + 1 if fraction >= 0.90 else 0
    if consecutive >= 3:
        print(f"controlled idle gate: {fraction:.1%} idle", file=sys.stderr)
        break
else:
    raise SystemExit("Runner is busy: refusing to produce performance evidence")
