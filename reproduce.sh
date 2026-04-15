#!/usr/bin/env bash
# Reproduces: @expo/fingerprint reports false-positive native changes
# when pnpm peer-dep paths reshuffle without any native file content change.
#
# Requirements: pnpm >= 9, node >= 18

set -e

echo "=== Step 1: Install with expo@52.0.48 (state A) ==="
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.dependencies.expo = '52.0.48';
delete pkg.pnpm;
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
"
rm -f pnpm-lock.yaml
pnpm install --silent

echo ""
echo "=== Step 2: Generate fingerprint.json (baseline) ==="
pnpm exec fingerprint fingerprint:generate > fingerprint.json
node -e "const fs = require('fs'); const json = JSON.parse(fs.readFileSync('fingerprint.json', 'utf8')); fs.writeFileSync('fingerprint.json', JSON.stringify(json, null, 2));"
echo "Saved fingerprint.json. Sample dir source paths:"
node -e "const d=JSON.parse(require('fs').readFileSync('fingerprint.json','utf8')); d.sources.filter(s=>s.type==='dir').slice(0,4).forEach(s=>console.log('  '+s.filePath));"

echo ""
echo "=== Step 3: Simulate peer-dep reshuffle: expo 52.0.48 -> 52.0.49 ==="
echo "(expo-asset, expo-constants etc. stay at SAME package versions; only peer resolution changes)"
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.dependencies.expo = '52.0.49';
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
"
rm -f pnpm-lock.yaml
pnpm install --silent

echo ""
echo "New dir source paths after reshuffle:"
pnpm exec fingerprint fingerprint:generate 2>/dev/null > /tmp/fingerprint_new.json
node -e "const d=JSON.parse(require('fs').readFileSync('/tmp/fingerprint_new.json','utf8')); d.sources.filter(s=>s.type==='dir').slice(0,4).forEach(s=>console.log('  '+s.filePath));"

echo ""
echo "=== Step 4: fingerprint diff ==="
pnpm exec fingerprint ./ fingerprint.json 2>/dev/null > fingerprint.diff.json
python3 - <<'PYEOF'
import json, sys

with open('/tmp/fp_diff.json') as f:
    diff = json.load(f)

if not diff:
    print("No changes (bug not reproduced)")
    sys.exit(0)

print(f"❌  BUG REPRODUCED: {len(diff)} change(s) reported despite no native file content change\n")
import re

added   = {item['addedSource']['filePath']   for item in diff if 'addedSource'   in item}
removed = {item['removedSource']['filePath'] for item in diff if 'removedSource' in item}

def pkg_key(path):
    """Extract 'pkg@version' from a pnpm virtual-store path, stripping the peer-dep suffix."""
    m = re.search(r'\.pnpm/([^/]+?)(?:_[^/]+)?/node_modules/', path)
    return m.group(1) if m else None

added_keys   = {pkg_key(p): p for p in added   if pkg_key(p)}
removed_keys = {pkg_key(p): p for p in removed if pkg_key(p)}
both = sorted(set(added_keys) & set(removed_keys))

print()
print("Observation:")
if both:
    for key in both:
        print(f"  {key} appears as both 'added' and 'removed':")
        print(f"    removed: {removed_keys[key]}")
        print(f"    added:   {added_keys[key]}")
    print()
    print("  Package version is IDENTICAL. Only the pnpm virtual-store peer-dep suffix changed.")
    print("  Native file content is byte-for-byte identical between the two virtual-store entries.")
else:
    print("  Could not find packages present in both added and removed sets.")
PYEOF
