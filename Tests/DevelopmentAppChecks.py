"""Offline safety checks for the local Dev updater; never builds or launches an app."""
from pathlib import Path
import plistlib
import runpy
import subprocess
import tempfile
from unittest.mock import patch

repo = Path(__file__).resolve().parent.parent
module = runpy.run_path(str(repo / 'scripts/dev-app.py'), run_name='development_checks')
namespace = module['watcher_running'].__globals__
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    pid_file = root / 'watch.pid'
    pid_file.write_text('123')
    script = str(repo / 'scripts/dev-app.py')
    with patch.dict(namespace, WATCH_PID=pid_file):
        for command, expected in [
            ('/Applications/Xcode.app/Python.app/Contents/MacOS/Python ' + script + ' --watch', True),
            ('/usr/bin/python3 ' + script + ' --watch', True),
            ('/usr/bin/python3 /other-checkout/scripts/dev-app.py --watch', False),
            ('/usr/bin/python3 ' + script, False),
            ('', False),
        ]:
            with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, stdout=command)):
                assert module['watcher_running']() == expected, command

    for directory in ['ImmichGallery', 'ImmichGalleryWidget', 'Shared', 'Config', 'ImmichGallery.xcodeproj', 'build']:
        (root / directory).mkdir()
    source = root / 'ImmichGallery/Example.swift'
    source.write_text('initial')
    with patch.dict(namespace, ROOT=root):
        initial = module['fingerprint']()
        (root / 'build/output.log').write_text('A build must not trigger another build')
        assert module['fingerprint']() == initial
        source.write_text('changed')
        assert module['fingerprint']() != initial

    dev = root / 'Dev.app'
    product = root / 'Build.app'
    for app in [dev, product]:
        (app / 'Contents').mkdir(parents=True)
        with (app / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleIdentifier': module['BUNDLE_ID'], 'CFBundleExecutable': 'ImmichGallery'}, stream)
    output = f'11 {dev}/Contents/MacOS/ImmichGallery\n12 {product}/Contents/MacOS/ImmichGallery\n13 /Applications/ImmichGallery.app/Contents/MacOS/ImmichGallery\n14 /some/other/app\n'
    with patch.dict(namespace, DESTINATION=dev, PRODUCT=product), patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, stdout=output)):
        assert module['development_pids']() == [11, 12], 'Production and unrelated processes must never be stopped'
print('Dev updater source detection, watcher identity, and production-process isolation passed')
