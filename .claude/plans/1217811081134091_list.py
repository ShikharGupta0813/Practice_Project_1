"""List admin route targets reachable under more than two distinct slugs.

Usage (repo root):
    python .claude/plans/1217811081134091_list.py            # reads origin/onestackcbs
    python .claude/plans/1217811081134091_list.py --raw      # don't expand (a|b) slug groups (reproduces the original 121)
"""
import collections
import re
import subprocess
import sys

FILES = ['routes.php', 'cbs-routes.php', 'production/routes.php', 'production/cbs-routes.php']
ROUTE = re.compile(r"\$route\[['\"]([^'\"]+)['\"]\]\s*=\s*['\"]([^'\"]+)['\"]")

expand = '--raw' not in sys.argv
routes = {}
for f in FILES:
    try:
        txt = subprocess.run(['git', 'show', 'origin/onestackcbs:application/config/' + f],
                             capture_output=True, check=True).stdout.decode('utf-8', 'ignore')
    except subprocess.CalledProcessError:
        continue
    for line in txt.splitlines():
        s = line.strip()
        if s.startswith('//') or s.startswith('#'):
            continue
        m = ROUTE.match(s)
        if m:
            routes[m.group(1)] = m.group(2)  # later files overwrite earlier ones, as CI does

by_target = collections.defaultdict(set)
for key, target in routes.items():
    parts = key.split('/')
    if parts[0] != 'admin' or len(parts) < 2:
        continue
    seg = parts[1]
    slugs = re.sub(r'^\((.*)\)$', r'\1', seg).split('|') if expand else [seg]
    tgt = re.sub(r'/\$\d.*$', '', target).lower()
    for s in slugs:
        by_target[tgt].add(re.sub(r'-(view|add|edit|delete)$', '', s))

multi = {t: s for t, s in by_target.items() if len(s) > 2}
print(f'routes {len(routes)}  admin targets {len(by_target)}  targets with >2 slugs {len(multi)}')
for t, s in sorted(multi.items(), key=lambda x: (-len(x[1]), x[0])):
    print(len(s), t, ', '.join(sorted(s)))
