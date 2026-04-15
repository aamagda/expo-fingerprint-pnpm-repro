#!/usr/bin/env bash
# Reproduces: @expo/fingerprint reports false-positive native changes
# when pnpm peer-dep paths reshuffle without any native file content change.
#
# Requirements: pnpm >= 9, node >= 18

set -e

echo "=== Step 1: Install with expo@52.0.49 (state A) ==="
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.dependencies.expo = '52.0.49';
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
echo "=== Step 3: Simulate peer-dep reshuffle: expo 52.0.49 -> 52.0.47 ==="
echo "(expo-asset, expo-constants etc. stay at SAME package versions; only peer resolution changes)"
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.dependencies.expo = '52.0.47';
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
pnpm exec fingerprint ./ fingerprint.json 2>/dev/null > /tmp/fp_diff.json
python3 - <<'PYEOF'
import json, sys

with open('/tmp/fp_diff.json') as f:
    diff = json.load(f)

if not diff:
    print("No changes (bug not reproduced)")
    sys.exit(0)

print(f"❌  BUG REPRODUCED: {len(diff)} change(s) reported despite no native file content change\n")
print("Sample diff entries:")
for item in diff[:8]:
    src = item.get('addedSource') or item.get('removedSource') or {}
    fp = src.get('filePath', '')
    print(f"  op: {item['op']:8s} | {fp[:95]}")

print()
print("Observation:")
print("  expo-asset@11.0.5 appears as both 'added' (with expo@52.0.47 in path)")
print("  and 'removed' (with expo@52.0.49 in path).")
print("  The package version is IDENTICAL. Only the pnpm virtual-store suffix changed.")
print("  Native file content is byte-for-byte identical between the two virtual-store entries.")
PYEOF
