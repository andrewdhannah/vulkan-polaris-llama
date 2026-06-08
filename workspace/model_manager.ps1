<#
.SYNOPSIS
    Model Manager for llama.cpp on RX 570 — switch, list, and query models
.DESCRIPTION
    Manages the llama-server-mini process for different GGUF models.
    Designed to be called from OpenWork or used interactively.

    Commands:
        list          - List all viable models
        status        - Show current server status and running model
        switch <name> - Stop current server, start with named model
        start <name>  - Start server with named model (no stop)
        stop          - Stop current server

    Examples:
        .\model_manager.ps1 list
        .\model_manager.ps1 status
        .\model_manager.ps1 switch phi-4
        .\model_manager.ps1 switch llama-3.2
#>

param(
    [Parameter(Position = 0)]
    [ValidateSet('list', 'status', 'switch', 'start', 'stop')]
    [string]$Command = 'status',

    [Parameter(Position = 1)]
    [string]$ModelName = ''
)

$ServerPath = "G:\llama.cpp\build_vs\bin\Release\llama-server-mini.exe"
$ModelsDir  = "G:\llama.cpp\models"
$DefaultPort = 9120
$ContextSize = 4096
$MaxPredict  = 1024

# ── Viable models (tested & working on RX 570 4GB) ──
$Models = @(
    @{
        name       = 'phi-4'
        display    = 'Phi-4-mini 3.8B Q4_K_M'
        file       = 'microsoft_Phi-4-mini-instruct-Q4_K_M.gguf'
        size_gb    = 2.32
        layers     = 33
        rank       = '🥇 Best All-Rounder'
        speed      = '14–51 tok/s'
        notes      = 'Best quality, math, and context retention'
    },
    @{
        name       = 'llama-3.2'
        display    = 'Llama 3.2 3B Q5_K_M'
        file       = 'Llama-3.2-3B-Instruct-Q5_K_M.gguf'
        size_gb    = 2.16
        layers     = 29
        rank       = '🥈 Fastest Daily Driver'
        speed      = '32–49 tok/s'
        notes      = 'Fastest generation, good all-around'
    },
    @{
        name       = 'gemma-3'
        display    = 'Gemma 3 4B Q4_K_M'
        file       = 'gemma-3-4b-it-Q4_K_M.gguf'
        size_gb    = 2.32
        layers     = 35
        rank       = '🥉 Best Verbose Assistant'
        speed      = '19–35 tok/s'
        notes      = 'Most thorough responses'
    },
    @{
        name       = 'qwen3'
        display    = 'Qwen3 4B Q4_K_M'
        file       = 'Qwen_Qwen3-4B-Q4_K_M.gguf'
        size_gb    = 2.33
        layers     = 37
        rank       = '4th — Needs >8K context'
        speed      = '22–40 tok/s'
        notes      = 'Good single-turn, <think> verbosity kills multi-turn at 4K ctx'
    }
)

# ── Helper functions ──

function Get-ServerProcess {
    Get-Process -Name 'llama-server-mini' -ErrorAction SilentlyContinue
}

function Get-ModelFromFile {
    param([string]$FilePath)
    foreach ($m in $Models) {
        $modelFile = Join-Path $ModelsDir $m.file
        if ($FilePath -and $FilePath -like "*$($m.file)*") { return $m }
    }
    return $null
}

function Get-CurrentModelName {
    $proc = Get-ServerProcess
    if (-not $proc) { return $null }
    # Try to extract model name from command line
    $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
    if ($cmdLine -match '-m\s+"([^"]+)"') {
        $modelPath = $Matches[1]
        foreach ($m in $Models) {
            if ($modelPath -like "*$($m.file)*") { return $m }
        }
        return @{display = "Unknown ($(Split-Path $modelPath -Leaf))" }
    }
    return $null
}

function Test-Health {
    $port = $DefaultPort
    try {
        $h = Invoke-RestMethod "http://localhost:$port/health" -TimeoutSec 3
        return $h.status -eq 'ok'
    } catch { return $false }
}

# ── Commands ──

function Invoke-List {
    Write-Host "`n=== Viable Models for RX 570 4GB ===" -ForegroundColor Cyan
    Write-Host ""

    $current = Get-CurrentModelName

    foreach ($m in $Models) {
        $modelPath = Join-Path $ModelsDir $m.file
        $exists = Test-Path $modelPath
        $isRunning = ($current -and $current.display -eq $m.display)

        $icon = if ($isRunning) { '▶' } else { ' ' }
        $statusColor = if ($isRunning) { 'Green' } elseif ($exists) { 'Gray' } else { 'DarkRed' }

        Write-Host " $icon $($m.rank)" -ForegroundColor $statusColor
        Write-Host "    Name:    $($m.display)" -ForegroundColor White
        Write-Host "    File:    $($m.file)" -ForegroundColor $statusColor
        Write-Host "    Size:    $($m.size_gb) GB | Layers: $($m.layers) | Speed: $($m.speed)" -ForegroundColor Gray
        Write-Host "    Notes:   $($m.notes)" -ForegroundColor DarkYellow
        if ($isRunning) { Write-Host '    STATUS:  ▶ Currently running' -ForegroundColor Green }
        Write-Host ""
    }

    # Also output JSON for OpenWork
    $result = @{
        models     = $Models
        current    = if ($current) { $current.display } else { $null }
        server_running = (Get-ServerProcess) -ne $null
        healthy    = Test-Health
    }
    return $result
}

function Invoke-Status {
    $proc = Get-ServerProcess
    $healthy = Test-Health

    Write-Host "`n=== Server Status ===" -ForegroundColor Cyan
    if ($proc) {
        Write-Host "  PID:      $($proc.Id)" -ForegroundColor Green
        $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
        if ($cmdLine) { Write-Host "  Process:  $cmdLine" -ForegroundColor Gray }
        Write-Host "  Health:   $(if ($healthy) { '✅ OK' } else { '❌ Not responding' })" -ForegroundColor $(if ($healthy) { 'Green' } else { 'Red' })
        Write-Host "  Port:     $DefaultPort" -ForegroundColor Gray

        $model = Get-CurrentModelName
        if ($model) {
            Write-Host "  Model:    $($model.display)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  No server running." -ForegroundColor Red
    }
    Write-Host ""

    return @{
        running        = $proc -ne $null
        pid            = if ($proc) { $proc.Id } else { $null }
        healthy        = $healthy
        current_model  = if ($model = Get-CurrentModelName) { $model.display } else { $null }
    }
}

function Invoke-Stop {
    $proc = Get-ServerProcess
    if ($proc) {
        Write-Host "Stopping server (PID $($proc.Id))..." -ForegroundColor Yellow
        $proc | Stop-Process -Force
        Start-Sleep 2
        Write-Host "Server stopped." -ForegroundColor Green
    } else {
        Write-Host "No server running." -ForegroundColor Gray
    }
}

function Invoke-Switch {
    param([string]$Name)
    if (-not $Name) {
        Write-Host "Usage: switch <modelname>" -ForegroundColor Red
        Write-Host "Valid names: $($Models.name -join ', ')" -ForegroundColor Gray
        return
    }

    $model = $Models | Where-Object { $_.name -eq $Name }
    if (-not $model) {
        Write-Host "Unknown model: $Name" -ForegroundColor Red
        Write-Host "Valid: $($Models.name -join ', ')" -ForegroundColor Gray
        return
    }

    $modelPath = Join-Path $ModelsDir $model.file
    if (-not (Test-Path $modelPath)) {
        Write-Host "Model file not found: $modelPath" -ForegroundColor Red
        return
    }

    # Stop existing
    Invoke-Stop

    # Start new
    Write-Host "Starting $($model.display)..." -ForegroundColor Cyan
    $logOut = "G:\temp\llama_$($model.name)_out.txt"
    $logErr = "G:\temp\llama_$($model.name)_err.txt"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ServerPath
    $psi.Arguments = "-m `"$modelPath`" -p $DefaultPort -c $ContextSize -ngl 99 -n $MaxPredict"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)

    Write-Host "  Loading..." -ForegroundColor Gray
    $loaded = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep 1
        try {
            $h = Invoke-RestMethod "http://localhost:$DefaultPort/health" -TimeoutSec 2
            if ($h.status -eq 'ok') { $loaded = $true; break }
        } catch {}
    }

    if ($loaded) {
        Write-Host "  ✅ $($model.display) is ready! (port $DefaultPort)" -ForegroundColor Green
    } else {
        Write-Host "  ❌ Failed to load. Check logs: $logErr" -ForegroundColor Red
    }
}

# ── Main ──

switch ($Command) {
    'list'   { Invoke-List }
    'status' { Invoke-Status }
    'switch' { Invoke-Switch -Name $ModelName }
    'start'  { Invoke-Switch -Name $ModelName }
    'stop'   { Invoke-Stop }
    default  { Invoke-Status }
}
