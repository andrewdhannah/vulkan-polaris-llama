@echo off
REM Start llama-server-mini with Qwen2.5 MOE 2x1.5B
set LLAMA_DIR=G:\llama.cpp
set MODEL=%LLAMA_DIR%\models\Qwen2.5-MOE-2X1.5B-DeepSeek-Uncensored-Censored-4B-D_AU-Q4_k_m.gguf
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
