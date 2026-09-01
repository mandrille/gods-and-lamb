@echo off
setlocal enabledelayedexpansion
rem ===========================================================================
rem  Gods and Lamb
rem
rem    RUN            build anything stale, then play on PC
rem    RUN play       play, no staleness check
rem    RUN assets     Blender: rebuild the GLB library and the layout, reimport
rem    RUN test       headless checks (renderer, layout, library, skin, clip)
rem    RUN shots      screenshots into godot\shots\
rem    RUN exe        Windows build into godot\builds\windows\
rem    RUN web        web build into godot\builds\web\, with a size report
rem    RUN serve      web build, then serve it at http://localhost:8712
rem    RUN gate       Blender: every asset through the asset gate
rem
rem  PC IS THE TARGET YOU DEVELOP AGAINST. Make the change, get it right on
rem  desktop, THEN run `RUN web` and read the size report before deciding
rem  whether the change is affordable. See docs/web-cost.md.
rem
rem  The two exe paths below are the only machine-specific lines in the repo.
rem ===========================================================================

set "BLENDER=C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
set "GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe"
set "GODOTC=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64_console.exe"

set "HERE=%~dp0"
set "BL=%HERE%blender"
set "GD=%HERE%godot"
set "MODE=%~1"
if "%MODE%"=="" set "MODE=auto"

if not exist "%BLENDER%" echo [WARN] Blender not found at %BLENDER%
if not exist "%GODOTC%" (
  echo [FAIL] Godot not found at %GODOTC%
  echo        Edit the GODOT/GODOTC lines at the top of this file.
  exit /b 1
)

if /i "%MODE%"=="assets" goto :assets
if /i "%MODE%"=="gate"   goto :gate
if /i "%MODE%"=="test"   goto :test
if /i "%MODE%"=="shots"  goto :shots
if /i "%MODE%"=="exe"    goto :exe
if /i "%MODE%"=="web"    goto :web
if /i "%MODE%"=="serve"  goto :serve
if /i "%MODE%"=="play"   goto :play
if /i "%MODE%"=="auto"   goto :auto
echo [FAIL] unknown mode "%MODE%". Try: play assets test shots exe web serve gate
exit /b 1

rem ---------------------------------------------------------------- auto
:auto
rem Is the exported layout older than anything it is built from? The TOOL
rem scripts are in the source list on purpose: leaving them out means editing
rem the exporter silently changes nothing, which cost the parent project a
rem session.
set "STALE=1"
if exist "%GD%\data\vale.json" (
  for /f %%R in ('powershell -NoProfile -Command ^
    "$t=(Get-Item '%GD%\data\vale.json').LastWriteTime; $n=(Get-ChildItem '%BL%\src\*.py','%BL%\assets\*\*.py','%BL%\assets\_kit\*.py','%BL%\build.py' -ErrorAction SilentlyContinue ^| Measure-Object LastWriteTime -Maximum).Maximum; if($n -gt $t){'1'}else{'0'}"') do set "STALE=%%R"
)
if "!STALE!"=="1" (
  echo [RUN] assets are stale -- rebuilding
  call :assets || exit /b 1
) else (
  echo [RUN] assets are current
)
goto :play

rem ---------------------------------------------------------------- assets
:assets
echo [RUN] Blender: exporting library + layout
pushd "%BL%"
"%BLENDER%" --background --factory-startup --python build.py -- export
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" (
  echo [FAIL] Blender export failed ^(exit %RC%^)
  exit /b %RC%
)
echo [RUN] Godot: importing
rem TWICE. Godot writes the .import sidecar on the first pass and can only
rem attach import settings on the second, so a brand-new .glb arrives with its
rem metadata present and never read.
"%GODOTC%" --headless --path "%GD%" --import >nul 2>&1
"%GODOTC%" --headless --path "%GD%" --import >nul 2>&1
if /i "%~1"=="assets" goto :test
exit /b 0

rem ---------------------------------------------------------------- gate
:gate
pushd "%BL%"
"%BLENDER%" --background --factory-startup --python build.py -- assets
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%

rem ---------------------------------------------------------------- test
:test
echo [RUN] headless checks
"%GODOTC%" --headless --path "%GD%" --script res://tools/vale_test.gd
if not "%ERRORLEVEL%"=="0" (
  echo.
  echo [FAIL] checks did not pass. NOT launching.
  echo        To play it anyway:  RUN play
  exit /b 1
)
if /i "%~1"=="test" exit /b 0
goto :play

rem ---------------------------------------------------------------- play
:play
echo [RUN] playing
"%GODOT%" --path "%GD%"
exit /b %ERRORLEVEL%

rem ---------------------------------------------------------------- shots
:shots
echo [RUN] screenshots into godot\shots\
rem NOT --headless: get_texture() needs a real swapchain.
"%GODOTC%" --path "%GD%" --resolution 1600x1000 --audio-driver Dummy --script res://tools/shots.gd
exit /b %ERRORLEVEL%

rem ---------------------------------------------------------------- exe
:exe
echo [RUN] Windows build
if not exist "%GD%\builds\windows" mkdir "%GD%\builds\windows"
"%GODOTC%" --headless --path "%GD%" --export-release "Windows Desktop" builds/windows/GodsAndLamb.exe
if exist "%GD%\builds\windows\GodsAndLamb.exe" (
  for %%F in ("%GD%\builds\windows\GodsAndLamb.exe") do echo [RUN] %%~zF bytes
) else (
  echo [FAIL] no exe was written
  exit /b 1
)
exit /b 0

rem ---------------------------------------------------------------- web
:web
echo [RUN] web build
if not exist "%GD%\builds\web" mkdir "%GD%\builds\web"
"%GODOTC%" --headless --path "%GD%" --export-release "Web" builds/web/index.html
if not exist "%GD%\builds\web\index.wasm" (
  echo [FAIL] no wasm was written -- the export failed
  exit /b 1
)
echo.
echo [WEB] what a server actually sends ^(gzip is what matters^):
powershell -NoProfile -Command ^
  "$ErrorActionPreference='Stop'; $tot=0; $totz=0;" ^
  "function Gz($p){ $in=[IO.File]::ReadAllBytes($p); $ms=New-Object IO.MemoryStream;" ^
  "$gz=New-Object IO.Compression.GZipStream($ms,[IO.Compression.CompressionLevel]::Optimal);" ^
  "$gz.Write($in,0,$in.Length); $gz.Close(); return $ms.ToArray().Length }" ^
  "foreach($f in 'index.wasm','index.pck','index.js','index.html'){" ^
  "$p=Join-Path '%GD%\builds\web' $f; if(-not(Test-Path $p)){continue};" ^
  "$r=(Get-Item $p).Length; $z=Gz $p; $tot+=$r; $totz+=$z;" ^
  "'{0,-14} {1,10:N0} raw {2,10:N0} gzip' -f $f,$r,$z }" ^
  "'{0,-14} {1,10:N0} raw {2,10:N0} gzip' -f 'TOTAL',$tot,$totz;" ^
  "$pck=Gz (Join-Path '%GD%\builds\web' 'index.pck');" ^
  "'' ; 'game content is {0:N1}%% of the gzipped download; the rest is the engine.' -f ($pck/$totz*100)"
echo.
echo [WEB] budget: the ENGINE is ~9.7 MB gzipped and fixed. Art and code changes
echo       move index.pck only. Judge a change against the pck, not the total.
exit /b 0

rem ---------------------------------------------------------------- serve
:serve
call :web || exit /b 1
echo.
echo [RUN] serving http://localhost:8712  ^(Ctrl+C to stop^)
pushd "%GD%\builds\web"
python -m http.server 8712
popd
exit /b 0
