@echo off
cd /d "%~dp0"
"%~dp0output\S0\runtime\godot.exe" --path "%~dp0." res://scenes/visibility_lab/visibility_lab.tscn
