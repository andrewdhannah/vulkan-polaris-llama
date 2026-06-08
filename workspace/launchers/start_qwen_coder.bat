@echo off
REM Start llama-server-mini with Qwen2.5 Coder 1.5B
set LLAMA_DIR=G:\llama.cpp
set MODEL=%LLAMA_DIR%\models\qwen2.5-coder-1.5b-instruct-q8_0.gguf
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
