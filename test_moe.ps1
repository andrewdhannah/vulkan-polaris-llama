$serverPath = "G:\vulkan-polaris-llama\start_server.bat"
$process = Start-Process -FilePath $serverPath -WindowStyle Normal -PassThru

# Give it time to load
Start-Sleep -Seconds 15

# Send a test request
try {
    $body = @{
        model = "qwen2.5-moe"
        messages = @(@{role="user"; content="Hello"})
        max_tokens = 32
        temperature = 0.7
        stream = $false
    }
    $response = Invoke-RestMethod -Uri "http://localhost:8080/v1/completions" -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json"
    Write-Host "`n=== Test Response ==="
    Write-Host ($response | ConvertTo-Json -Depth 10)
} catch {
    Write-Host "Error during request: $_"
} finally {
    # Optionally stop the process if still running
    if ($process -and !$process.HasExited) {
        Write-Host "`nStopping server process..."
        $process | Stop-Process -Force
    }
}