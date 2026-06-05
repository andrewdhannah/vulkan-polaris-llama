@echo off
REM ===================================================
REM start_server.bat — Vulkan Polaris llama.cpp Server
REM ===================================================
REM Edit the two paths below for your setup.
REM
REM LLAMA_DIR: where you cloned and built llama.cpp
REM MODEL:     path to your GGUF model file
REM ===================================================

set LLAMA_DIR=G:\llama.cpp
set MODEL=G:\Downloads\Qwen2.5-MOE-2X1.5B-DeepSeek-Uncensored-Censored-4B-D_AU-Q4_k_m.gguf
set PORT=8080
set N_CTX=32768
set NGL=99
set N_PREDICT=512

REM ---- Try several common binary locations ----
if exist "%LLAMA_DIR%\build\bin\Release\llama-server-mini.exe" (
    set BIN="%LLAMA_DIR%\build\bin\Release\llama-server-mini.exe"
) else if exist "%LLAMA_DIR%\build\examples\server-mini\Release\llama-server-mini.exe" (
    set BIN="%LLAMA_DIR%\build\examples\server-mini\Release\llama-server-mini.exe"
) else (
    echo [ERROR] Could not find llama-server-mini.exe
    echo Looked in:
    echo   %%LLAMA_DIR%%\build\bin\Release\
    echo   %%LLAMA_DIR%%\build\examples\server-mini\Release\
    echo.
    echo Edit LLAMA_DIR in this script or build the server first.
    pause
    exit /b 1
)

if not exist %MODEL% (
    echo [ERROR] Model not found: %MODEL%
    echo Edit the MODEL variable in this script.
    pause
    exit /b 1
)

echo =============================================
echo  Vulkan Polaris — llama.cpp Server
echo =============================================
echo  Binary: %BIN%
echo  Model:  %MODEL%
echo  Port:   %PORT%
echo  GPU:    %NGL% layers
echo  Ctx:    %N_CTX% tokens
echo =============================================
echo.
echo Starting server... (wait ~12s for model load)
echo.

%BIN% -m %MODEL% -p %PORT% -c %N_CTX% -ngl %NGL% -n %N_PREDICT%

echo.
echo Server stopped.
pause
