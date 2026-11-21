@echo off
if not exist "%~dp0instalar.ps1" (
  echo Primero descomprime el zip: clic derecho en el zip, "Extraer todo", y abre instalar.bat desde la carpeta nueva.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar.ps1"
if errorlevel 1 pause
