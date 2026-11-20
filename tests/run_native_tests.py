#!/usr/bin/env python3
"""Run JVM contract tests against the actual patched production source.

Usage: python3 run_native_tests.py SOURCE_ROOT OUTPUT_DIR
Requires JDK and kotlinc. The Android APIs alone are replaced by deterministic
test doubles; the production method and failure classifier are not rewritten.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

if len(sys.argv) != 3:
    raise SystemExit(__doc__)

source_root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
test_root = Path(__file__).resolve().parent
native = source_root / 'android/app/src/main/kotlin/ee/nekoko/nlpa2'
plugin = native / 'OmapiPlugin.kt'
classifier = native / 'OmapiOpenFailures.kt'
text = plugin.read_text()
start = text.index('    private fun handleOpenChannel(')
end_marker = '\n    @RequiresApi(Build.VERSION_CODES.P)\n    private fun handleCloseChannel('
end = text.index(end_marker, start)
method = text[start:end].rstrip()
if not method.endswith('}'):
    raise SystemExit('Cannot extract complete production method')

output.mkdir(parents=True, exist_ok=True)
harness = (test_root / 'NativeOpenHarness.kt.in').read_text()
if harness.count('@@METHOD@@') != 1:
    raise SystemExit('Expected exactly one production method placeholder')
generated = output / 'NativeOpenHarness.kt'
generated.write_text(harness.replace('@@METHOD@@', method))
(output / 'source-provenance.json').write_text(json.dumps({
    'method_source': str(plugin.relative_to(source_root)),
    'method_sha256': hashlib.sha256(method.encode()).hexdigest(),
    'plugin_sha256': hashlib.sha256(plugin.read_bytes()).hexdigest(),
    'classifier_sha256': hashlib.sha256(classifier.read_bytes()).hexdigest(),
    'scope': 'JVM doubles; not Android or real-card validation',
}, indent=2) + '\n')

jar = output / 'native-tests.jar'
compile_result = subprocess.run(
    ['kotlinc', str(classifier), str(generated), '-include-runtime', '-d', str(jar)],
    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
)
(output / 'compile.log').write_text(compile_result.stdout)
if compile_result.returncode:
    print(compile_result.stdout)
    raise SystemExit(compile_result.returncode)
result = subprocess.run(
    ['java', '-jar', str(jar)], text=True, stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT, timeout=60,
)
(output / 'test.log').write_text(result.stdout)
print(result.stdout, end='')
raise SystemExit(result.returncode)
