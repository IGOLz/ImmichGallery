"""Check compiled Swift string extraction against Italian catalogs after a Debug build."""
import itertools
import glob
import json
import re
import subprocess
from pathlib import Path

catalogs = {p.stem: json.loads(p.read_text())['strings'] for p in Path('ImmichGallery').glob('*.xcstrings')}
def leaves(node):
    if 'stringUnit' in node:
        yield node['stringUnit']
    for child in node.get('variations', {}).get('plural', {}).values():
        yield from leaves(child)


def placeholders(value):
    return re.findall(r'%(?:\d+\$)?(?:lld|@)|\$\{[^}]+\}', value)


def check(key, localization):
    substitutions = localization.get('substitutions', {})
    if substitutions:
        expanded = [localization['stringUnit']['value']]
        for name, value in substitutions.items():
            assert value['formatSpecifier'] == 'lld', key
            assert set(value['variations']['plural']) >= {'one', 'other'}, key
            variants = list(leaves(value))
            assert all(v['state'] == 'translated' for v in variants), key
            expanded = [base.replace(f'%#@{name}@', leaf['value'].replace('%arg', f"%{value['argNum']}$lld"))
                        for base, leaf in itertools.product(expanded, variants)]
        expected = placeholders(key)
        for value in expanded:
            actual = placeholders(value)
            assert len(actual) == len(expected), key
            assert sorted(int(re.search(r'%(\d+)\$', token)[1]) for token in actual) == list(range(1, len(expected) + 1)), key
    else:
        for leaf in leaves(localization):
            assert leaf['state'] == 'translated', key
            assert placeholders(key) == placeholders(leaf['value']), key


checked = set()
for filename in glob.glob('build/DerivedData/**/*.stringsdata', recursive=True):
    extraction = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', filename]))
    for table, entries in extraction.get('tables', {}).items():
        for entry in entries:
            key = entry['key']
            check(key, catalogs[table][key]['localizations']['it'])
            checked.add((table, key))
assert checked, 'Build first to extract localizable strings'
print(f'Checked Italian coverage and placeholders for {len(checked)} extracted strings.')

for key, entry in catalogs['Localizable'].items():
    for localization in entry.get('localizations', {}).values():
        check(key, localization)
