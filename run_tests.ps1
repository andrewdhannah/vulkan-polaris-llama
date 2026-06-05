# PowerShell test script for the locally-running llama-server

# --------------------------------------------------------------
# Configuration
# --------------------------------------------------------------
$baseUrl = "http://localhost:8080"
$model    = "qwen2.5-moe"

# --------------------------------------------------------------
# Helper: simple GET request (used for /v1/models)
# --------------------------------------------------------------
function Get-Json($endpoint) {
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl$endpoint" -Method Get -ErrorAction Stop
        return $response
    } catch {
        Write-Error "GET $endpoint failed: $_"
        return $null
    }
}

# --------------------------------------------------------------
# Helper: POST request for chat/completions
# --------------------------------------------------------------
function Post-ChatCompletion($payload) {
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/v1/chat/completions" `
                                      -Method Post `
                                      -Headers @{ "Content-Type" = "application/json" } `
                                      -Body ($payload | ConvertTo-Json -Depth 10) `
                                      -ErrorAction Stop
        return $response
    } catch {
        Write-Error "POST /v1/chat/completions failed: $_"
        return $null
    }
}

# --------------------------------------------------------------
# 1. Retrieve the list of available models
# --------------------------------------------------------------
Write-Host "`n=== Checking /v1/models ==="
$modelsResponse = Get-Json("/v1/models")
if ($modelsResponse) {
    $modelsResponse | ConvertTo-Json -Depth 5 | Out-File -FilePath "models_response.json"
    Write-Host "Models response saved to models_response.json"
} else {
    Write-Host "No models response received."
}

# --------------------------------------------------------------
# 2. Send a test completion request
# --------------------------------------------------------------
$testPayload = @{
    model      = $model
    messages   = @(@{ role = "user"; content = "Hello" })
    max_tokens = 32
    temperature = 0.7
    stream     = $false
}
Write-Host "`n=== Sending test completion request ==="
$completionResponse = Post-ChatCompletion $testPayload
if ($completionResponse) {
    $completionResponse | ConvertTo-Json -Depth 10 | Out-File -FilePath "completion_response.json"
    Write-Host "Completion response saved to completion_response.json"
} else {
    Write-Host "No completion response received."
}

# --------------------------------------------------------------
# 3. Save a short summary for documentation
# --------------------------------------------------------------
$summary = @'
## Test Results (generated $(Get-Date -Format u))

### /v1/models
[See models_response.json]

### /v1/chat/completions (test payload)
[See completion_response.json]

'@

$summary | Set-Content -FilePath "test_summary.md" -Encoding utf8
Write-Host "`n=== Summary written to test_summary.md ==="