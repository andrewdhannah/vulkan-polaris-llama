@echo off
title llama.cpp Vulkan Server (Polaris)
echo ============================================
echo  llama.cpp Vulkan Server
echo  GPU: Radeon RX 570 (Polaris)
echo  Model: Qwen 2.5 Coder 1.5B Q8_0
echo  Port: 8080
echo ============================================
echo.
echo Access from your Mac:
echo   curl http://192.168.0.158:8080/v1/chat/completions ^
echo     -H "Content-Type: application/json" ^
echo     -d "{"""messages""":[{"""role""":"""user""","""content""":"""Hello"""}]}"
echo.
echo Or in OpenWork: Settings ^> AI Providers ^> Custom Provider
echo   Base URL: http://192.168.0.158:8080/v1
echo.
echo Loading model (this takes ~12s)...
echo.

"G:\llama.cpp\build_vs\bin\Release\llama-server-mini.exe" -m "G:\Downloads\qwen2.5-coder-1.5b-instruct-q8_0.gguf" -p 8080 -c 32768 -ngl 99

echo.
echo Server exited. Press any key to close.
pause >nul
