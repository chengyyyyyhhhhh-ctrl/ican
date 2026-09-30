@echo off
cd /d "%~dp0"
python -m PyInstaller --noconfirm --clean --onefile --windowed --name DirectionMonitor app.py
if errorlevel 1 (
  echo.
  echo Build failed. Install PyInstaller first: python -m pip install pyinstaller
  pause
)
