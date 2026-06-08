@echo off
REM Start llama-server-mini with Gemma 4 4B (Q2_K_P)
set LLAMA_DIR=G:\llama.cpp
set MODEL=%LLAMA_DIR%\models\Gemma-4-E2B-Uncensored-HauhauCS-Aggressive-Q2_K_P.gguf
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
