#!/usr/bin/env python3
"""Local Godot launcher and validation, independent of parent-project commands."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'output/current_validation'
CHECKS = [
    ('opening', 'opening_route_test'),
    ('cleanup', 'project_cleanup_test'), ('isometric', 'isometric_test'),
    ('controls', 'hades_controls_test'),
    ('abilities', 'ability_regression_test'), ('movement', 'slime_movement_test'),
    ('whip', 'whip_contact_test'), ('trace', 'slime_trace_edge_test'),
    ('spitter', 'spitter_model_test'), ('save', 'checkpoint_store_test'),
]


def main():
    parser = argparse.ArgumentParser(description='Запуск изометрической игры')
    parser.add_argument('mode', choices=['game', 'editor', 'test', 'capture'])
    args = parser.parse_args()
    candidates = [os.environ.get('GODOT_BIN'),
                  '/Applications/Godot.app/Contents/MacOS/Godot',
                  str(Path.home() / 'Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot'),
                  shutil.which('godot')]
    binary = next((candidate for candidate in candidates if candidate and Path(candidate).is_file()), None)
    if binary is None:
        parser.exit(2, 'Godot не найден. Задайте GODOT_BIN.\n')
    OUTPUT.mkdir(parents=True, exist_ok=True)

    def run(name, command_args, checked=False):
        command = [binary, '--path', str(ROOT), '--log-file', str(OUTPUT / (name + '.engine.log')), *command_args]
        result = subprocess.run(command, capture_output=checked, text=True)
        if checked:
            (OUTPUT / (name + '.stdout.log')).write_text(result.stdout)
            (OUTPUT / (name + '.stderr.log')).write_text(result.stderr)
            (OUTPUT / (name + '.command.json')).write_text(json.dumps({'command': command, 'exitCode': result.returncode}, indent=2) + '\n')
            failed = re.search(r'SCRIPT ERROR|Parse Error|^FAIL[ :]', result.stdout + result.stderr, re.M)
            print(('PASS' if result.returncode == 0 and not failed else 'FAIL') + ' ' + name, flush=True)
            for line in result.stdout.splitlines():
                if re.search(r'RESULT|SUMMARY|BLOCKED|FAIL ', line):
                    print(line, flush=True)
            if failed:
                return 1
        return result.returncode

    if args.mode == 'test':
        cases = [('import', ['--headless', '--editor', '--import', '--quit'])]
        cases += [(name, ['--headless', '--fixed-fps', '60', '--script', 'res://tests/' + script + '.gd']) for name, script in CHECKS]
        cases += [('settings', ['--headless', '--fixed-fps', '60', 'res://tests/slime_settings_test.tscn'])]
        for name, command_args in cases:
            code = run(name, command_args, checked=True)
            if code:
                return code
        return 0
    if args.mode == 'capture':
        return run('capture', ['--resolution', '1280x720', '--fixed-fps', '60', '--script', 'res://tests/opening_route_test.gd', '--', '--capture'], checked=True)
    return run(args.mode, ['--editor'] if args.mode == 'editor' else [])


if __name__ == '__main__':
    raise SystemExit(main())
