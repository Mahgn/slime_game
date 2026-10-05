@echo off
set "ROOT=%~dp0"
set "PROJECT=%ROOT:~0,-1%"
set "GODOT=%ROOT%output\S0\runtime\godot.exe"
if not exist "%GODOT%" (
  echo Godot executable not found: "%GODOT%"
  pause
  exit /b 1
)
start "" /D "%PROJECT%" "%GODOT%" --path "%PROJECT%" --scene res://scenes/art_review/slime_platform_course.tscn
