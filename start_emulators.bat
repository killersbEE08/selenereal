@echo off
rem Starts the Firebase emulators for local development (Functions use the real Gemini API via functions\.secret.local).
set JAVA_HOME=C:\Program Files\Android\Android Studio\jbr
set PATH=%JAVA_HOME%\bin;%PATH%
set FUNCTIONS_DISCOVERY_TIMEOUT=120
cd /d %~dp0
call npm --prefix functions run build || exit /b 1
firebase emulators:start --project selene-ai-34251 --import=.emulator-data --export-on-exit=.emulator-data
