"""Check compiled Swift string extraction against Italian catalogs after a Debug build."""
import glob
import json
import re
import subprocess
from pathlib import Path

catalogs = {p.stem: json.loads(p.read_text())['strings'] for p in Path('ImmichGallery').glob('*.xcstrings')}
checked = set()
for filename in glob.glob('build/DerivedData/**/*.stringsdata', recursive=True):
    extraction = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', filename]))
    for table, entries in extraction.get('tables', {}).items():
        for entry in entries:
            key = entry['key']
            translated = catalogs[table][key]['localizations']['it']['stringUnit']
            assert translated['state'] == 'translated', key
            assert re.findall(r'%(?:\d+\$)?(?:lld|@)|\$\{[^}]+\}', key) == re.findall(
                r'%(?:\d+\$)?(?:lld|@)|\$\{[^}]+\}', translated['value']), key
            checked.add((table, key))
assert checked, 'Build first to extract localizable strings'
print(f'Checked Italian coverage and placeholders for {len(checked)} extracted strings.')
