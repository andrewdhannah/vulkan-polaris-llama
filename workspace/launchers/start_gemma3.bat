@echo off
REM Start llama-server-mini with Gemma 3 4B
set LLAMA_DIR=G:\llama.cpp
set MODEL=%LLAMA_DIR%\models\gemma-3-4b-it-Q4_K_M.gguf
set PORT=8080
set N_CTX=16384
set NGL=99
set N_PREDICT=1024

if not exist "%MODEL%" (
    echo [ERROR] Model not found: %MODEL%
    pause
    exit /b 1
)

"%LLAMA_DIR%\build_vs\bin\Release\llama-server-mini.exe" -m "%MODEL%" -p %PORT% -c %N_CTX% -ngl %NGL% -n %N_PREDICT%
pause
