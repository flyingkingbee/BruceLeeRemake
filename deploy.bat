@echo off
setlocal EnableExtensions
cd /d "%~dp0"

rem Usage: deploy.bat [version]
rem Builds Release and makes dist\BruceLeeRemake-Setup-<version>.exe with
rem Inno Setup 6. The version defaults to 1.0.0.
set "VERSION=%~1"
if "%VERSION%"=="" set "VERSION=1.0.0"

call "%~dp0build.bat" release
if errorlevel 1 exit /b 1

set "ISCC="
if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not defined ISCC (
  echo Could not find Inno Setup 6. Install it with:
  echo   winget install --id JRSoftware.InnoSetup -e
  exit /b 1
)

"%ISCC%" /Q /DAppVersion=%VERSION% installer\BruceLee.iss
if errorlevel 1 exit /b 1
echo Made dist\BruceLeeRemake-Setup-%VERSION%.exe
exit /b 0
