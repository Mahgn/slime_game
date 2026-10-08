@echo off
chcp 65001 >nul
setlocal
set "SLIME_GODOT=%GODOT_BIN%"
if not defined SLIME_GODOT set "SLIME_GODOT=%~dp0output\S0\runtime\godot.exe"
if not exist "%SLIME_GODOT%" (
    echo Godot не найден. Укажите путь к движку в GODOT_BIN.
    pause
    exit /b 1
)
start "" "%SLIME_GODOT%" --path "%~dp0." res://scenes/keepers/keepers_facility.tscn
