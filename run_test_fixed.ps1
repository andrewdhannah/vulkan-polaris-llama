# PowerShell script to test the locally-running llama server
# ---------------------------------------------------------
# 1. Ensure any stray server process is killed
# ---------------------------------------------------------
Stop-Process -Name llama-server-mini -ErrorAction SilentlyContinue

# ---------------------------------------------------------
# 2. Start the server (background)
# ---------------------------------------------------------
Start-Process -FilePath "G:\vulkan-polaris-llama\start_server.bat" -WindowStyle Normal

# ---------------------------------------------------------
# 3. Wait until the HTTP endpoint is reachable (max 30s)
# ---------------------------------------------------------
$maxAttempts = 30
for ($i = 0; $i -lt $maxAttempts; $i++) {
    try {
        $null = Invoke-RestMethod -Uri "http://localhost:8080/v1/models" -Method Get -ErrorAction Stop
        Write-Host "`n✅ Server is up! Continuing..."
        break
    } catch {
        Write-Host "⏳ Attempt $($i+1)/$maxAttempts – still waiting..."
        Start-Sleep -Seconds 1
    }
}
if ($i -eq $maxAttempts) {
    Write-Error "❌ Server did not become ready within 30 seconds. Abort."
    exit 1
}

# ---------------------------------------------------------
# 4. Retrieve the list of available models and save it
# ---------------------------------------------------------
try {
    $modelsResponse = Invoke-RestMethod -Uri "http://localhost:8080/v1/models" -Method Get -ErrorAction Stop
    $modelsResponse | ConvertTo-Json -Depth 5 | Out-File -FilePath "docs\models_response.json"
    Write-Host "📄 Saved models list to docs\models_response.json"
} catch {
    Write-Error "Failed to fetch /v1/models: $_"
    exit 1
}

# ---------------------------------------------------------
# 5. Prepare the test payload
# ---------------------------------------------------------
$testPayload = @{
    model      = "qwen2.5-moe"
    messages   = @(@{ role = "user"; content = "Hello" })
    max_tokens = 32
    temperature = 0.7
    stream     = $false
}
$testPayloadJson = $testPayload | ConvertTo-Json -Depth 10

# ---------------------------------------------------------
# 6. Send the test completion request and save the response
# ---------------------------------------------------------
try {
    $completionResponse = Invoke-RestMethod -Uri "http://localhost:8080/v1/chat/completions" `
                                          -Method Post `
                                          -Headers @{ "Content-Type" = "application/json" } `
                                          -Body $testPayloadJson `
                                          -ErrorAction Stop
    $completionResponse | ConvertTo-Json -Depth 10 | Out-File -FilePath "docs\completion_response.json"
    Write-Host "📄 Saved completion response to docs\completion_response.json"
} catch {
    Write-Error "Completion request failed: $_"
    exit 1
}

# ---------------------------------------------------------
# 8. Create a markdown summary for documentation
# ---------------------------------------------------------
$summary = @'
## Test Results (generated $(Get-Date -Format u))

### /v1/models
[See docs/models_response.json]

### /v1/chat/completions (payload sent)
[See docs/completion_response.json]

'@

$summary | Set-Content -Path "docs\test_summary.md" -Encoding utf8
Write-Host "📝 Summary written to docs/test_summary.md"