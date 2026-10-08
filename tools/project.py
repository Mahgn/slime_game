#!/usr/bin/env python3
"""Local Godot launcher and validation, independent of parent-project commands."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'output/current_validation'
CHECKS = [
    ('keepers_facility', 'keepers_facility_test'),
    ('keepers_world', 'keepers_world_test'),
    ('keepers_world_ai', 'keepers_world_ai_test'),
    ('keepers_run', 'keepers_run_test'),
    ('keepers_run_edges', 'keepers_run_edges_test'),
    ('keepers', 'keepers_level_test'),
    ('cutaway', 'wall_cutaway_test'),
    ('cutaway_aim', 'cutaway_aim_test'),
    ('foundation', 'isometric_foundation_test'),
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
    parser.add_argument('--output', type=Path, default=OUTPUT, help='Каталог журналов проверок')
    parser.add_argument('--timeout', type=float, default=240, help='Лимит одной проверки в секундах')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout должен быть больше нуля')
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    candidates = [os.environ.get('GODOT_BIN'),
                  str(ROOT / 'output/S0/runtime/godot.exe'),
                  '/Applications/Godot.app/Contents/MacOS/Godot',
                  str(Path.home() / 'Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot'),
                  shutil.which('godot'), shutil.which('godot4')]
    binary = next((candidate for candidate in candidates if candidate and Path(candidate).is_file()), None)
    if binary is None:
        parser.exit(2, 'Godot не найден. Задайте GODOT_BIN.\n')
    binary = str(Path(binary).resolve())
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    def run(name, command_args, checked=False):
        command = [binary, '--path', str(ROOT), '--log-file', str(output / (name + '.engine.log')), *command_args]
        try:
            result = subprocess.run(command, cwd=ROOT, capture_output=checked, text=True,
                                    encoding='utf-8', errors='replace',
                                    timeout=args.timeout if checked else None)
        except subprocess.TimeoutExpired as error:
            def decoded(value):
                return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else (value or '')
            result = subprocess.CompletedProcess(command, 124, decoded(error.stdout),
                                                 decoded(error.stderr) + '\nFAIL timeout\n')
        if checked:
            (output / (name + '.stdout.log')).write_text(result.stdout, encoding='utf-8')
            (output / (name + '.stderr.log')).write_text(result.stderr, encoding='utf-8')
            (output / (name + '.command.json')).write_text(json.dumps({'command': command, 'exitCode': result.returncode}, indent=2) + '\n', encoding='utf-8')
            failed = re.search(r'SCRIPT ERROR|Parse Error|^ERROR:|^FAIL[ :]', result.stdout + result.stderr, re.M)
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
        exit_code = 0
        for name, command_args in cases:
            code = run(name, command_args, checked=True)
            if name == 'import' and code:
                return code
            if code:
                exit_code = code
        return exit_code
    if args.mode == 'capture':
        return run('capture', ['--resolution', '1280x720', '--fixed-fps', '60', '--script', 'res://tests/opening_route_test.gd', '--', '--capture'], checked=True)
    return run(args.mode, ['--editor'] if args.mode == 'editor' else [])


if __name__ == '__main__':
    raise SystemExit(main())
