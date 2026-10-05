@echo off
setlocal
set "SLIME_PROJECT=%~dp0"
set "SLIME_GODOT=%SLIME_PROJECT%output\S0\runtime\godot.exe"
if not exist "%SLIME_GODOT%" (
  echo Godot binary not found: %SLIME_GODOT%
  exit /b 1
)
start "Slime First Floor" "%SLIME_GODOT%" --path "%SLIME_PROJECT%." --windowed --resolution 1280x720 --scene res://scenes/levels/first_floor.tscn
