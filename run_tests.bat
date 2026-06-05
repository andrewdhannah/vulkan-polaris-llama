@echo off
REM Create docs folder
mkdir -p G:\vulkan-polaris-llama\docs

REM Fetch models list
curl -s http://localhost:8080/v1/models > G:\vulkan-polaris-llama\docs\models_response.json

REM Send test completion
curl -s -X POST http://localhost:8080/v1/chat/completions -H "Content-Type: application/json" -d "{\"model\":\"qwen2.5-moe\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"max_tokens\":32,\"temperature\":0.7,\"stream\":false}" > G:\vulkan-polaris-llama\docs\completion_response.json

REM Write markdown summary
echo ## Test Results > G:\vulkan-polaris-llama\docs\test_summary.md
echo. >> G:\vulkan-polaris-llama\docs\test_summary.md
echo ### /v1/models >> G:\vulkan-polaris-llama\docs\test_summary.md
echo [See models_response.json] >> G:\vulkan-polaris-llama\docs\test_summary.md
echo. >> G:\vulkan-polaris-llama\docs\test_summary.md
echo ### /v1/chat/completions >> G:\vulkan-polaris-llama\docs\test_summary.md
echo [See completion_response.json] >> G:\vulkan-polaris-llama\docs\test_summary.md