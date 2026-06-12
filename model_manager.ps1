<#
.SYNOPSIS
    Model Manager for llama.cpp on RX 570 -- hardened
.DESCRIPTION
    Manages llama-server-mini processes (chat + embedding).
    Supports identity validation, orphan cleanup, graceful shutdown,
    port conflict detection, pre-flight checks, and full diagnostics.

    Commands:
        list             - List all viable models
        status           - Show current chat server status
        switch <name>    - Stop chat server, start with named model
        start <name>     - Start chat server with named model (no stop)
        stop             - Stop chat server gracefully
        embed-start      - Start embedding server on port 9122
        embed-stop       - Stop embedding server gracefully
        embed-status     - Show embedding server status
        diagnose         - Comprehensive system health check

    Examples:
        .\model_manager.ps1 list
        .\model_manager.ps1 switch phi-4
        .\model_manager.ps1 embed-start
        .\model_manager.ps1 diagnose
#>

param(
    [Parameter(Position = 0)]
    [ValidateSet('list', 'status', 'switch', 'start', 'stop',
                 'embed-start', 'embed-stop', 'embed-status', 'diagnose')]
    [string]$Command = 'status',

    [Parameter(Position = 1)]
    [string]$ModelName = ''
)

$ErrorActionPreference = 'Continue'

# ─── Paths and configuration ────────────────────────────────────────────────

$ServerPath   = "G:\llama.cpp\build_vs\bin\Release\llama-server-mini.exe"
$ModelsDir    = "G:\llama.cpp\models"
$DefaultPort  = 9120
$ContextSize  = 4096
$MaxPredict   = 1024

$EmbedModelPath = "G:\llamacpp\snowflake-arctic-embed-m-long-Q4_0.gguf"
$EmbedPort      = 9122
$EmbedContext   = 8192

$PidDir         = "G:\temp"
$ChatPidFile    = "$PidDir\llama_manager_9120.pid"
$EmbedPidFile   = "$PidDir\llama_manager_9122.pid"

$StartupTimeoutSec = 180
$PollIntervalSec   = 3

# ─── Viable chat models ─────────────────────────────────────────────────────

$Models = @(
    @{
        name    = 'phi-4'
        display = 'Phi-4-mini 3.8B Q4_K_M'
        file    = 'microsoft_Phi-4-mini-instruct-Q4_K_M.gguf'
        size_gb = 2.32
        layers  = 33
        rank    = 'Best All-Rounder'
        speed   = '14-51 tok/s'
        notes   = 'Best quality, math, and context retention'
    },
    @{
        name    = 'llama-3.2'
        display = 'Llama 3.2 3B Q5_K_M'
        file    = 'Llama-3.2-3B-Instruct-Q5_K_M.gguf'
        size_gb = 2.16
        layers  = 29
        rank    = 'Fastest Daily Driver'
        speed   = '32-49 tok/s'
        notes   = 'Fastest generation, good all-around'
    },
    @{
        name    = 'gemma-3'
        display = 'Gemma 3 4B Q4_K_M'
        file    = 'gemma-3-4b-it-Q4_K_M.gguf'
        size_gb = 2.32
        layers  = 35
        rank    = 'Best Verbose Assistant'
        speed   = '19-35 tok/s'
        notes   = 'Most thorough responses'
    },
    @{
        name    = 'qwen3'
        display = 'Qwen3 4B Q4_K_M'
        file    = 'Qwen_Qwen3-4B-Q4_K_M.gguf'
        size_gb = 2.33
        layers  = 37
        rank    = '4th -- Needs >8K context'
        speed   = '22-40 tok/s'
        notes   = 'Good single-turn, <think> verbosity kills multi-turn at 4K ctx'
    }
)

# ─── Helper: PID file management ──────────────────────────────────────────

function Get-PidFilePath { param([int]$Port)
    if ($Port -eq $DefaultPort) { return $ChatPidFile }
    if ($Port -eq $EmbedPort)   { return $EmbedPidFile }
    return "$PidDir\llama_manager_$Port.pid"
}

function Read-PidFile { param([int]$Port)
    $path = Get-PidFilePath -Port $Port
    if (-not (Test-Path $path)) { return $null }
    try {
        $content = (Get-Content $path -Raw).Trim()
        if ($content -match '^\d+$') { return [int]$content }
    } catch {}
    return $null
}

function Write-PidFile { param([int]$Port, [int]$ProcessId)
    $path = Get-PidFilePath -Port $Port
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -Path $path -Value "$ProcessId" -NoNewline
}

function Remove-PidFile { param([int]$Port)
    $path = Get-PidFilePath -Port $Port
    if (Test-Path $path) { Remove-Item $path -Force }
}

# ─── Helper: process management ──────────────────────────────────────────

function Get-ServerProcess {
    Get-Process -Name 'llama-server-mini' -ErrorAction SilentlyContinue
}

function Get-ProcessByPort {
    param([int]$Port)
    Get-ServerProcess | Where-Object {
        $cmd = Get-ProcessCmdLine -ProcessId $_.Id
        $cmd -like "*$Port*"
    } | Select-Object -First 1
}

function Get-ProcessCmdLine {
    param([int]$ProcessId)
    try {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
        return $proc.CommandLine
    } catch {
        # Fallback: use WMI via Get-WmiObject (available in PS5.1)
        try {
            $proc = Get-WmiObject Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
            return $proc.CommandLine
        } catch { return $null }
    }
}

function Get-ProcessModelArg {
    param([int]$ProcessId)
    $cmdLine = Get-ProcessCmdLine -ProcessId $ProcessId
    if ($cmdLine -match '-m\s+"([^"]+)"') { return $Matches[1] }
    return $null
}

function Get-CurrentModelName {
    $proc = Get-ProcessByPort -Port $DefaultPort
    if (-not $proc) { return $null }
    $cmdLine = Get-ProcessCmdLine -ProcessId $proc.Id
    if ($cmdLine -match '-m\s+"([^"]+)"') {
        $modelPath = $Matches[1]
        foreach ($m in $Models) {
            if ($modelPath -like "*$($m.file)*") { return $m }
        }
        return @{display = "Unknown ($(Split-Path $modelPath -Leaf))"; file = (Split-Path $modelPath -Leaf) }
    }
    return $null
}

function Get-EmbedProcess {
    Get-ProcessByPort -Port $EmbedPort
}

function Get-ModelFromFile {
    param([string]$FilePath)
    foreach ($m in $Models) {
        $modelFile = Join-Path $ModelsDir $m.file
        if ($FilePath -and $FilePath -like "*$($m.file)*") { return $m }
    }
    return $null
}

# ─── Helper: health and identity ─────────────────────────────────────────

function Test-Health {
    param([int]$Port = $DefaultPort)
    try {
        return (Invoke-RestMethod "http://localhost:$Port/health" -TimeoutSec 3)
    } catch { return $null }
}

function Test-PortOpen {
    param([int]$Port)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect("127.0.0.1", $Port)
        $tcp.Close()
        return $true
    } catch { return $false }
}

function Test-PortConflict {
    param([int]$Port)
    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -ErrorAction Stop
        # Skip stale entries: TimeWait state (kernel finishing TCP close) or PID 0 (phantom process)
        if ($conn.State -eq 'TimeWait') { return $null }
        if ($conn.OwningProcess -eq 0) { return $null }
        $owner = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
        if (-not $owner) { return $null } # process no longer exists
        if ($owner.ProcessName -eq 'llama-server-mini') { return $null } # our own process
        return @{ ProcessName = $owner.ProcessName; ProcessId = $conn.OwningProcess }
    } catch { return $null }
}

function Classify-Identity {
    param(
        [string]$RegistryFile,
        [string]$ProcessPath,
        [string]$HealthModel,
        [string]$ExpectedAlias = ''
    )
    $regMatchProc   = ($ProcessPath -and $ProcessPath -like "*$RegistryFile*")
    $regMatchHealth = ($HealthModel -and $HealthModel -like "*$RegistryFile*")
    $aliasMatch     = ($ExpectedAlias -and $HealthModel -eq $ExpectedAlias)
    $procLeaf = if ($ProcessPath) { Split-Path $ProcessPath -Leaf } else { '' }
    $procMatchHealth = ($ProcessPath -and $HealthModel -and ($ProcessPath -like "*$HealthModel*" -or $HealthModel -like "*$procLeaf*"))

    # If health matches expected alias, treat as strong confirmation
    if ($aliasMatch) { return @{ state = 'VERIFIED'; detail = 'Health alias matches expected name' } }
    if ($regMatchProc -and $regMatchHealth) { return @{ state = 'VERIFIED'; detail = 'All three sources match' } }
    if ($regMatchProc -and -not $regMatchHealth) { return @{ state = 'HEALTH_IDENTITY_DRIFT'; detail = 'Registry + process match, health differs' } }
    if ($regMatchHealth -and -not $regMatchProc) { return @{ state = 'PROCESS_DRIFT'; detail = 'Registry + health match, process differs' } }
    if ($procMatchHealth -and -not $regMatchProc) { return @{ state = 'REGISTRY_STALE'; detail = 'Process + health match, registry differs' } }
    return @{ state = 'UNTRUSTED_RUNTIME'; detail = 'None of the three sources match' }
}

# ─── Helper: pre-flight checks ──────────────────────────────────────────

function Invoke-PreFlightCheck {
    param([string]$Label, [string]$ModelPath, [int]$Port)
    $ok = $true

    Write-Host "  Checking binary: $ServerPath..." -NoNewline
    if (Test-Path $ServerPath) { Write-Host " OK" -ForegroundColor Green }
    else { Write-Host " MISSING" -ForegroundColor Red; $ok = $false }

    Write-Host "  Checking model: $ModelPath..." -NoNewline
    if (Test-Path $ModelPath) { Write-Host " OK" -ForegroundColor Green }
    else { Write-Host " MISSING" -ForegroundColor Red; $ok = $false }

    Write-Host "  Checking port $Port..." -NoNewline
    $conflict = Test-PortConflict -Port $Port
    if (-not $conflict) { Write-Host " Free" -ForegroundColor Green }
    else {
        Write-Host " CONFLICT (owned by $($conflict.ProcessName) PID $($conflict.ProcessId))" -ForegroundColor Red
        $ok = $false
    }

    Write-Host "  Checking Vulkan device..." -NoNewline
    try {
        $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like "*Radeon*" -or $_.Name -like "*AMD*" } | Select-Object -First 1
        if ($gpu) { Write-Host " $($gpu.Name)" -ForegroundColor Green }
        else { Write-Host " No AMD/Radeon GPU found (may use fallback)" -ForegroundColor Yellow }
    } catch { Write-Host " Cannot check" -ForegroundColor Gray }

    if (-not $ok) {
        Write-Host "  Pre-flight FAILED. Correct the issues above before starting." -ForegroundColor Red
    }
    return $ok
}

# ─── Helper: graceful stop ─────────────────────────────────────────────

function Stop-ProcessGracefully {
    param([int]$ProcessId, [string]$ProcessLabel)
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) { return }

    Write-Host "  Stopping $ProcessLabel (PID $ProcessId)..." -ForegroundColor Yellow

    # Step 1: Try taskkill without /F (sends close to console windows)
    $result = & "taskkill" "/PID", "$ProcessId" 2>&1
    Start-Sleep -Seconds 3

    # Step 2: Check if still alive
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "  Graceful shutdown timed out, force killing..." -ForegroundColor Yellow
        $proc | Stop-Process -Force
        Start-Sleep -Seconds 2
    }

    Write-Host "  $ProcessLabel stopped." -ForegroundColor Green
}

# ─── Helper: PID cleanup (orphan detection) ────────────────────────────

function Invoke-StalePidCleanup {
    param([int]$Port)
    $savedPid = Read-PidFile -Port $Port
    if (-not $savedPid) { return $null }

    $running = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
    if (-not $running) {
        Write-Host "  Stale PID file found (PID $savedPid, no longer running). Cleaning up." -ForegroundColor Yellow
        Remove-PidFile -Port $Port
        return $null
    }

    # Process is running -- check if it's actually ours
    $cmd = Get-ProcessCmdLine -ProcessId $savedPid
    if ($cmd -like "*$Port*") {
        Write-Host "  Server already running (PID $savedPid, port $Port) per PID file." -ForegroundColor Yellow
        return $savedPid
    }

    # PID reused by another process
    Write-Host "  Stale PID file (PID $savedPid reused by $($running.ProcessName)). Cleaning up." -ForegroundColor Yellow
    Remove-PidFile -Port $Port
    return $null
}

# ─── Startup state machine (shared by chat and embed) ──────────────────

function Wait-ForServerStart {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$Port,
        [string]$LogErr
    )
    $state = 'STARTING'
    $reportedModel = $null
    $startTime = Get-Date
    $lastProgressMsg = 0

    for ($i = 0; $i -lt ($StartupTimeoutSec / $PollIntervalSec); $i++) {
        Start-Sleep -Seconds $PollIntervalSec

        if ($Process.HasExited) {
            Write-Host "  [FAILED_TO_START] Process exited (code $($Process.ExitCode)). Check: $LogErr" -ForegroundColor Red
            return @{ state = 'FAILED_TO_START' }
        }

        $elapsed = [math]::Round((New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds)
        if ($elapsed -ge $lastProgressMsg + 30) {
            $lastProgressMsg = $elapsed
            Write-Host "  ... still waiting ($elapsed s elapsed)..." -ForegroundColor DarkYellow
        }

        if ($state -eq 'STARTING' -and (Test-PortOpen -Port $Port)) {
            $state = 'LISTENING'
            Write-Host "  [LISTENING] Port $Port is open..." -ForegroundColor Gray
        }

        if ($state -eq 'LISTENING') {
            $h = Test-Health -Port $Port
            if ($h -and $h.status -eq 'ok') {
                $state = 'HEALTH_RESPONDED'
                $reportedModel = $h.model
                $total = [math]::Round((New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds)
                Write-Host "  [HEALTH_RESPONDED] Health OK after ${total}s (reported: $reportedModel)" -ForegroundColor Gray
                return @{ state = 'HEALTH_RESPONDED'; model = $reportedModel }
            }
        }
    }

    if ($Process.HasExited) {
        Write-Host "  [FAILED_TO_START] Process exited before healthy. Check: $LogErr" -ForegroundColor Red
        return @{ state = 'FAILED_TO_START' }
    }
    Write-Host "  [FAILED_TO_START] Timed out after ${StartupTimeoutSec}s. Check: $LogErr" -ForegroundColor Red
    return @{ state = 'FAILED_TO_START' }
}

# ═══════════════════════════════════════════════════════════════════════════
# COMMANDS
# ═══════════════════════════════════════════════════════════════════════════

# ─── list ────────────────────────────────────────────────────────────────

function Invoke-List {
    Write-Host "`n=== Viable Models for RX 570 4GB ===" -ForegroundColor Cyan
    Write-Host ""

    $current = Get-CurrentModelName

    foreach ($m in $Models) {
        $modelPath = Join-Path $ModelsDir $m.file
        $exists = Test-Path $modelPath
        $isRunning = ($current -and $current.display -eq $m.display)

        $icon = if ($isRunning) { '[RUNNING]' } else { '         ' }
        $statusColor = if ($isRunning) { 'Green' } elseif ($exists) { 'Gray' } else { 'DarkRed' }

        Write-Host " $icon $($m.rank)" -ForegroundColor $statusColor
        Write-Host "    Name:    $($m.display)" -ForegroundColor White
        Write-Host "    File:    $($m.file)" -ForegroundColor $statusColor
        Write-Host "    Size:    $($m.size_gb) GB | Layers: $($m.layers) | Speed: $($m.speed)" -ForegroundColor Gray
        Write-Host "    Notes:   $($m.notes)" -ForegroundColor DarkYellow
        if ($isRunning) { Write-Host "    STATUS:  Currently running on port $DefaultPort" -ForegroundColor Green }
        Write-Host ""
    }

    return @{
        models     = $Models
        current    = if ($current) { $current.display } else { $null }
        server_running = (Get-ServerProcess) -ne $null
        healthy    = (Test-Health -Port $DefaultPort) -ne $null
    }
}

# ─── status ──────────────────────────────────────────────────────────────

function Invoke-Status {
    $proc = Get-ProcessByPort -Port $DefaultPort
    $healthy = Test-Health -Port $DefaultPort

    Write-Host "`n=== Server Status (port $DefaultPort) ===" -ForegroundColor Cyan
    if ($proc) {
        Write-Host "  PID:      $($proc.Id)" -ForegroundColor Green
        $cmdLine = Get-ProcessCmdLine -ProcessId $proc.Id
        if ($cmdLine) { Write-Host "  Process:  $cmdLine" -ForegroundColor Gray }

        $model = Get-CurrentModelName
        if ($model) { Write-Host "  Registry: $($model.file)" -ForegroundColor Yellow }

        $procPath = Get-ProcessModelArg -ProcessId $proc.Id
        if ($procPath) { Write-Host "  Process:  $(Split-Path $procPath -Leaf)" -ForegroundColor Yellow }

        if ($healthy) {
            Write-Host "  Health:   OK (reported: $($healthy.model))" -ForegroundColor $(if ($healthy.model -like "*$($model.file)*" -or $healthy.model -eq $model.name) { 'Green' } else { 'Yellow' })
            $classification = Classify-Identity -RegistryFile $model.file -ProcessPath $procPath -HealthModel $healthy.model -ExpectedAlias $model.name
            $color = switch ($classification.state) {
                'VERIFIED'              { 'Green' }
                'HEALTH_IDENTITY_DRIFT' { 'Yellow' }
                'PROCESS_DRIFT'         { 'Red' }
                'REGISTRY_STALE'        { 'Cyan' }
                'UNTRUSTED_RUNTIME'     { 'Red' }
                default                 { 'Gray' }
            }
            Write-Host "  Identity: $($classification.state) - $($classification.detail)" -ForegroundColor $color
        } else {
            Write-Host "  Health:   Not responding" -ForegroundColor Red
        }

        # PID file check
        $savedPid = Read-PidFile -Port $DefaultPort
        if ($savedPid -and $savedPid -eq $proc.Id) {
            Write-Host "  PID file: Consistent (PID $savedPid)" -ForegroundColor Green
        } elseif ($savedPid) {
            Write-Host "  PID file: Stale (saved $savedPid, actual $($proc.Id))" -ForegroundColor Yellow
        } else {
            Write-Host "  PID file: None" -ForegroundColor Gray
        }

        Write-Host "  Port:     $DefaultPort" -ForegroundColor Gray
    } else {
        Write-Host "  No server running on port $DefaultPort." -ForegroundColor Red
    }
    Write-Host ""

    return @{
        running        = $proc -ne $null
        pid            = if ($proc) { $proc.Id } else { $null }
        healthy        = $healthy -ne $null
        current_model  = if ($model = Get-CurrentModelName) { $model.display } else { $null }
    }
}

# ─── stop ────────────────────────────────────────────────────────────────

function Invoke-Stop {
    $proc = Get-ProcessByPort -Port $DefaultPort
    if ($proc) {
        Stop-ProcessGracefully -ProcessId $proc.Id -ProcessLabel "Chat server"
        Remove-PidFile -Port $DefaultPort
    } else {
        Write-Host "No server running on port $DefaultPort." -ForegroundColor Gray
        Remove-PidFile -Port $DefaultPort
    }
}

# ─── switch / start ──────────────────────────────────────────────────────

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

    # ── Pre-flight checks ──
    Write-Host "`n-- Pre-flight checks --" -ForegroundColor Cyan
    if (-not (Invoke-PreFlightCheck -Label $model.display -ModelPath $modelPath -Port $DefaultPort)) {
        return
    }

    # ── Orphan cleanup ──
    $orphanPid = Invoke-StalePidCleanup -Port $DefaultPort
    if ($orphanPid) {
        Write-Host "  Server already running on port $DefaultPort (PID $orphanPid). Use 'stop' first." -ForegroundColor Yellow
        return
    }

    # ── Stop existing ──
    Invoke-Stop
    Start-Sleep -Seconds 1

    # ── Launch ──
    Write-Host "`n-- Starting $($model.display) (alias: $($model.name)) --" -ForegroundColor Cyan
    $logOut = "G:\temp\llama_$($model.name)_out.txt"
    $logErr = "G:\temp\llama_$($model.name)_err.txt"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ServerPath
    $psi.Arguments = "-m `"$modelPath`" -p $DefaultPort -c $ContextSize -ngl 99 -n $MaxPredict --alias `"$($model.name)`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    try {
        $p = [System.Diagnostics.Process]::Start($psi)
    } catch {
        Write-Host "  [FAILED_TO_START] Could not launch process: $_" -ForegroundColor Red
        return
    }

    Write-Host "  [STARTING] Process launched (PID $($p.Id))..." -ForegroundColor Gray
    Write-Host "  Model loading started (Vulkan, ~60-120s)..." -ForegroundColor DarkYellow
    Write-PidFile -Port $DefaultPort -ProcessId $p.Id

    # ── State machine: wait for startup ──
    $startResult = Wait-ForServerStart -Process $p -Port $DefaultPort -LogErr $logErr

    if ($startResult.state -eq 'FAILED_TO_START') {
        Remove-PidFile -Port $DefaultPort
        return
    }

    # ── Identity validation ──
    $procPath = Get-ProcessModelArg -ProcessId $p.Id
    $registryFile = $model.file
    $reportedModel = $startResult.model

    $classification = Classify-Identity -RegistryFile $registryFile -ProcessPath $procPath -HealthModel $reportedModel -ExpectedAlias $model.name

    switch ($classification.state) {
        'VERIFIED' {
            Write-Host "  [IDENTITY_MATCHED] VERIFIED - All three sources confirm: $($model.display)" -ForegroundColor Green
        }
        'HEALTH_IDENTITY_DRIFT' {
            Write-Host "  [IDENTITY_MISMATCH] HEALTH_IDENTITY_DRIFT" -ForegroundColor Yellow
            Write-Host "    Registry:  $registryFile" -ForegroundColor Yellow
            Write-Host "    Process:   $(Split-Path $procPath -Leaf)" -ForegroundColor Green
            Write-Host "    Health:    $reportedModel" -ForegroundColor Yellow
            Write-Host "    Note: Server is running the correct model. /health reports alias name." -ForegroundColor Cyan
            Write-Host "    (Expected --alias `"$($model.name)`", but health reported something else)" -ForegroundColor DarkGray
        }
        'PROCESS_DRIFT' {
            Write-Host "  [IDENTITY_MISMATCH] PROCESS_DRIFT" -ForegroundColor Red
            Write-Host "    Registry:  $registryFile" -ForegroundColor Yellow
            Write-Host "    Process:   $(Split-Path $procPath -Leaf)" -ForegroundColor Red
            Write-Host "    Health:    $reportedModel" -ForegroundColor Yellow
        }
        'REGISTRY_STALE' {
            Write-Host "  [IDENTITY_MISMATCH] REGISTRY_STALE" -ForegroundColor Cyan
            Write-Host "    Registry:  $registryFile" -ForegroundColor Yellow
            Write-Host "    Process:   $(Split-Path $procPath -Leaf)" -ForegroundColor Green
            Write-Host "    Health:    $reportedModel" -ForegroundColor Green
            Write-Host "    Note: Registry entry may be outdated." -ForegroundColor Cyan
        }
        'UNTRUSTED_RUNTIME' {
            Write-Host "  [IDENTITY_MISMATCH] UNTRUSTED_RUNTIME" -ForegroundColor Red
            Write-Host "    Registry:  $registryFile" -ForegroundColor Red
            Write-Host "    Process:   $(Split-Path $procPath -Leaf)" -ForegroundColor Red
            Write-Host "    Health:    $reportedModel" -ForegroundColor Red
        }
    }

    Write-Host "  Server ready on port $DefaultPort (PID $($p.Id))" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# EMBEDDING COMMANDS
# ═══════════════════════════════════════════════════════════════════════════

# ─── embed-start ──────────────────────────────────────────────────────────

function Invoke-EmbedStart {
    Write-Host "`n=== Embedding Server ===" -ForegroundColor Cyan

    if (-not (Test-Path $EmbedModelPath)) {
        Write-Host "  Model file not found: $EmbedModelPath" -ForegroundColor Red
        return
    }

    # ── Pre-flight ──
    Write-Host "-- Pre-flight checks --" -ForegroundColor Cyan
    if (-not (Invoke-PreFlightCheck -Label "Embedding" -ModelPath $EmbedModelPath -Port $EmbedPort)) {
        return
    }

    # ── Already running? ──
    $existing = Get-EmbedProcess
    if ($existing) {
        Write-Host "  Embedding server already running (PID $($existing.Id), port $EmbedPort)" -ForegroundColor Yellow
        $embedRoleOk = $false
        try {
            $body = @{ input = "role check"; model = "snowflake-arctic-embed" } | ConvertTo-Json
            $r = Invoke-RestMethod "http://localhost:$EmbedPort/v1/embeddings" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 5
            if ($r -and ($r.data -or $r.embeddings)) { $embedRoleOk = $true }
        } catch {}
        if ($embedRoleOk) {
            Write-Host "  [EMBEDDING_ROLE_OK] /v1/embeddings responding" -ForegroundColor Green
        } else {
            Write-Host "  [EMBEDDING_ROLE_FAILED] /v1/embeddings not available" -ForegroundColor Red
        }
        return
    }

    # ── Orphan cleanup ──
    $orphanPid = Invoke-StalePidCleanup -Port $EmbedPort
    if ($orphanPid) {
        Write-Host "  Server already running on port $EmbedPort (PID $orphanPid). Use 'embed-stop' first." -ForegroundColor Yellow
        return
    }

    # ── Launch ──
    Write-Host "  Starting embedding server (alias: snowflake-arctic-embed-long)..." -ForegroundColor Gray
    Write-Host "  Model: $(Split-Path $EmbedModelPath -Leaf)" -ForegroundColor Gray
    Write-Host "  Port:  $EmbedPort" -ForegroundColor Gray

    $logOut = "G:\temp\llama_embed_out.txt"
    $logErr = "G:\temp\llama_embed_err.txt"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ServerPath
    $psi.Arguments = "-m `"$EmbedModelPath`" -p $EmbedPort -c $EmbedContext -ngl 99 --alias `"snowflake-arctic-embed-long`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    try {
        $p = [System.Diagnostics.Process]::Start($psi)
    } catch {
        Write-Host "  [FAILED_TO_START] Could not launch process: $_" -ForegroundColor Red
        return
    }

    Write-Host "  [STARTING] Process launched (PID $($p.Id))..." -ForegroundColor Gray
    Write-Host "  Model loading started (Vulkan, ~60-120s)..." -ForegroundColor DarkYellow
    Write-PidFile -Port $EmbedPort -ProcessId $p.Id

    # ── State machine ──
    $startResult = Wait-ForServerStart -Process $p -Port $EmbedPort -LogErr $logErr

    if ($startResult.state -eq 'FAILED_TO_START') {
        Remove-PidFile -Port $EmbedPort
        return
    }

    # ── Identity check ──
    $procPath = Get-ProcessModelArg -ProcessId $p.Id
    $expectedFile = Split-Path $EmbedModelPath -Leaf
    $healthModel = $startResult.model

    $classification = Classify-Identity -RegistryFile $expectedFile -ProcessPath $procPath -HealthModel $healthModel -ExpectedAlias 'snowflake-arctic-embed-long'
    Write-Host "  [IDENTITY_CHECK] $($classification.state) - $($classification.detail)" -ForegroundColor $(
        if ($classification.state -eq 'VERIFIED') { 'Green' } else { 'Yellow' }
    )

    # ── Role validation ──
    $embedRoleOk = $false
    try {
        $body = @{ input = "role validation test"; model = "snowflake-arctic-embed" } | ConvertTo-Json
        $r = Invoke-RestMethod "http://localhost:$EmbedPort/v1/embeddings" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 5
        if ($r -and ($r.data -or $r.embeddings)) { $embedRoleOk = $true }
    } catch {}

    if ($embedRoleOk) {
        Write-Host "  [EMBEDDING_ROLE_OK] /v1/embeddings responded successfully" -ForegroundColor Green
        Write-Host "  Embedding server ready on port $EmbedPort (PID $($p.Id))" -ForegroundColor Green
    } else {
        Write-Host "  [EMBEDDING_ROLE_FAILED] /v1/embeddings not available or returned no data" -ForegroundColor Red
        Write-Host "    Process alive, port open, but retrieval role is NOT operational." -ForegroundColor Red
        Write-Host "    llama-server-mini.exe lacks --embedding flag support." -ForegroundColor Cyan
        Write-Host "    Server running on port $EmbedPort (PID $($p.Id)) but cannot serve embeddings." -ForegroundColor Yellow
    }
}

# ─── embed-stop ───────────────────────────────────────────────────────────

function Invoke-EmbedStop {
    $proc = Get-EmbedProcess
    if ($proc) {
        Stop-ProcessGracefully -ProcessId $proc.Id -ProcessLabel "Embedding server"
        Remove-PidFile -Port $EmbedPort
    } else {
        Write-Host "No embedding server running on port $EmbedPort." -ForegroundColor Gray
        Remove-PidFile -Port $EmbedPort
    }
}

# ─── embed-status ─────────────────────────────────────────────────────────

function Invoke-EmbedStatus {
    Write-Host "`n=== Embedding Server Status (port $EmbedPort) ===" -ForegroundColor Cyan

    $proc = Get-EmbedProcess
    if ($proc) {
        Write-Host "  PID:      $($proc.Id)" -ForegroundColor Green
        $cmdLine = Get-ProcessCmdLine -ProcessId $proc.Id
        if ($cmdLine) { Write-Host "  Process:  $cmdLine" -ForegroundColor Gray }

        $healthy = Test-Health -Port $EmbedPort
        if ($healthy) {
            Write-Host "  Health:   OK (reported: $($healthy.model))" -ForegroundColor Green

            $procPath = Get-ProcessModelArg -ProcessId $proc.Id
            $expectedFile = Split-Path $EmbedModelPath -Leaf
            $classification = Classify-Identity -RegistryFile $expectedFile -ProcessPath $procPath -HealthModel $healthy.model -ExpectedAlias 'snowflake-arctic-embed-long'
            Write-Host "  Identity: $($classification.state) - $($classification.detail)" -ForegroundColor $(
                if ($classification.state -eq 'VERIFIED') { 'Green' } else { 'Yellow' }
            )
        } else {
            Write-Host "  Health:   Not responding" -ForegroundColor Red
        }

        # PID file check
        $savedPid = Read-PidFile -Port $EmbedPort
        if ($savedPid -and $savedPid -eq $proc.Id) {
            Write-Host "  PID file: Consistent (PID $savedPid)" -ForegroundColor Green
        } elseif ($savedPid) {
            Write-Host "  PID file: Stale (saved $savedPid, actual $($proc.Id))" -ForegroundColor Yellow
        } else {
            Write-Host "  PID file: None" -ForegroundColor Gray
        }

        # Role validation
        $embedRoleOk = $false
        try {
            $body = @{ input = "test"; model = "snowflake-arctic-embed" } | ConvertTo-Json
            $r = Invoke-RestMethod "http://localhost:$EmbedPort/v1/embeddings" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 5
            if ($r -and ($r.data -or $r.embeddings)) { $embedRoleOk = $true }
        } catch {}

        if ($embedRoleOk) {
            Write-Host "  Embeddings endpoint: AVAILABLE [EMBEDDING_ROLE_OK]" -ForegroundColor Green
        } else {
            Write-Host "  Embeddings endpoint: NOT AVAILABLE [EMBEDDING_ROLE_FAILED]" -ForegroundColor Red
            Write-Host "    Process alive, port open, but retrieval role is NOT operational." -ForegroundColor Red
        }
    } else {
        Write-Host "  No embedding server running on port $EmbedPort." -ForegroundColor Red
    }
    Write-Host ""

    return @{
        running = $proc -ne $null
        pid     = if ($proc) { $proc.Id } else { $null }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# DIAGNOSE
# ═══════════════════════════════════════════════════════════════════════════

function Invoke-Diagnose {
    Write-Host "`n"
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "  llama.cpp System Diagnostics" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host ""

    # ── Environment ──
    Write-Host "-- Environment --" -ForegroundColor Cyan
    Write-Host "  Host:          $env:COMPUTERNAME"
    Write-Host "  OS:            $(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)"
    Write-Host "  PowerShell:    $($PSVersionTable.PSVersion)"
    Write-Host "  Repo:          G:\llama.cpp (HEAD 7c158fb)"
    Write-Host "  Disk G: free:  $([math]::Round((Get-PSDrive G).Free / 1GB, 1)) GB"
    Write-Host ""

    # ── Binary ──
    Write-Host "-- Binary --" -ForegroundColor Cyan
    $binExists = Test-Path $ServerPath
    if ($binExists) {
        $binInfo = Get-Item $ServerPath
        Write-Host "  $ServerPath" -ForegroundColor Green
        Write-Host "  Size:  $([math]::Round($binInfo.Length / 1MB, 1)) MB"
        Write-Host "  Date:  $($binInfo.LastWriteTime)"
    } else {
        Write-Host "  $ServerPath" -ForegroundColor Red
        Write-Host "  MISSING" -ForegroundColor Red
    }
    Write-Host ""

    # ── GPU / Vulkan ──
    Write-Host "-- GPU --" -ForegroundColor Cyan
    try {
        $gpus = Get-CimInstance Win32_VideoController
        foreach ($gpu in $gpus) {
            $vram = if ($gpu.AdapterRAM) { "$([math]::Round($gpu.AdapterRAM / 1GB, 1)) GB" } else { "Unknown" }
            $icon = if ($gpu.Name -like "*Radeon*") { 'GPU' } elseif ($gpu.Name -like "*Intel*") { 'CPU' } else { '   ' }
            Write-Host "  $icon $($gpu.Name) ($vram VRAM, driver $($gpu.DriverVersion))"
        }
    } catch { Write-Host "  Cannot enumerate GPU: $_" -ForegroundColor Red }
    Write-Host ""

    # ── Ports and processes ──
    Write-Host "-- Ports and Processes --" -ForegroundColor Cyan

    foreach ($entry in @(@{Label='Chat'; Port=$DefaultPort; PidFile=$ChatPidFile},
                         @{Label='Embed'; Port=$EmbedPort; PidFile=$EmbedPidFile},
                         @{Label='Unused'; Port=9121; PidFile=$null})) {

        $portOpen = Test-PortOpen -Port $entry.Port
        $health = Test-Health -Port $entry.Port
        $proc = Get-ProcessByPort -Port $entry.Port
        $conflict = Test-PortConflict -Port $entry.Port

        $label = "{0,-7}" -f $entry.Label
        Write-Host "  Port $($entry.Port):" -NoNewline
        if ($portOpen) { Write-Host " LISTENING" -NoNewline -ForegroundColor Green } else { Write-Host " CLOSED" -NoNewline -ForegroundColor Gray }

        if ($conflict) {
            Write-Host " [CONFLICT: $($conflict.ProcessName) PID $($conflict.ProcessId)]" -ForegroundColor Red
            continue
        }

        if ($proc) {
            Write-Host " (PID $($proc.Id), " -NoNewline
            $procPath = Get-ProcessModelArg -ProcessId $proc.Id
            if ($procPath) { Write-Host "$(Split-Path $procPath -Leaf))" -NoNewline } else { Write-Host "no -m arg)" -NoNewline }

            if ($health) {
                Write-Host " health: $($health.model)" -ForegroundColor $(if ($health.status -eq 'ok') { 'Green' } else { 'Red' })
            } else {
                Write-Host " health: NOT RESPONDING" -ForegroundColor Red
            }

            # Identity classification
            if ($label -ne 'Unused ') {
                $pPath = Get-ProcessModelArg -ProcessId $proc.Id
                $hModel = if ($health) { $health.model } else { '' }
                $regFile = if ($label -eq 'Chat   ') {
                    $m = Get-CurrentModelName
                    if ($m) { $m.file } else { '' }
                } else {
                    Split-Path $EmbedModelPath -Leaf
                }
                if ($regFile -and $pPath -and $hModel) {
                    $aliasName = if ($label -eq 'Chat   ') {
                        $m = Get-CurrentModelName
                        if ($m) { $m.name } else { '' }
                    } else { 'snowflake-arctic-embed-long' }
                    $class = Classify-Identity -RegistryFile $regFile -ProcessPath $pPath -HealthModel $hModel -ExpectedAlias $aliasName
                    Write-Host "           Identity: $($class.state) - $($class.detail)" -ForegroundColor $(
                        switch ($class.state) {
                            'VERIFIED' { 'Green' }
                            'HEALTH_IDENTITY_DRIFT' { 'Yellow' }
                            'PROCESS_DRIFT' { 'Red' }
                            'REGISTRY_STALE' { 'Cyan' }
                            'UNTRUSTED_RUNTIME' { 'Red' }
                            default { 'Gray' }
                        }
                    )
                }
            }

            # PID file consistency
            if ($entry.PidFile) {
                $savedPid = Read-PidFile -Port $entry.Port
                if ($savedPid -and $savedPid -eq $proc.Id) {
                    Write-Host "           PID file: OK" -ForegroundColor Green
                } elseif ($savedPid) {
                    Write-Host "           PID file: STALE (saved $savedPid, actual $($proc.Id))" -ForegroundColor Yellow
                } else {
                    Write-Host "           PID file: MISSING" -ForegroundColor Yellow
                }
            }
        } elseif ($portOpen) {
            Write-Host " (unknown process)" -ForegroundColor Yellow
            if ($entry.PidFile) {
                $savedPid = Read-PidFile -Port $entry.Port
                if ($savedPid) {
                    Write-Host "    PID file: $savedPid (port open but process unrecognized)" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "" -NoNewline
            if ($entry.PidFile) {
                $savedPid = Read-PidFile -Port $entry.Port
                if ($savedPid) {
                    Write-Host "    PID file: STALE (PID $savedPid, port closed)" -ForegroundColor Yellow
                } else {
                    Write-Host "    PID file: none" -ForegroundColor Gray
                }
            }
        }
    }
    Write-Host ""

    # ── Models ──
    Write-Host "-- Model Files --" -ForegroundColor Cyan
    foreach ($m in $Models) {
        $mPath = Join-Path $ModelsDir $m.file
        $exists = Test-Path $mPath
        $sizeStr = if ($exists) { "$([math]::Round((Get-Item $mPath).Length / 1GB, 2)) GB" } else { 'MISSING' }
        Write-Host "  $($m.name): $($m.file) [$sizeStr]" -ForegroundColor $(if ($exists) { 'Gray' } else { 'Red' })
    }
    $embedExists = Test-Path $EmbedModelPath
    $embedSizeStr = if ($embedExists) { "$([math]::Round((Get-Item $EmbedModelPath).Length / 1GB, 2)) GB" } else { 'MISSING' }
    Write-Host "  embed:  $(Split-Path $EmbedModelPath -Leaf) [$embedSizeStr]" -ForegroundColor $(if ($embedExists) { 'Gray' } else { 'Red' })
    Write-Host ""

    # ── Summary grid ──
    Write-Host "-- Summary --" -ForegroundColor Cyan
    Write-Host "  Port  Role      Model                         Identity                    Status"
    Write-Host "  ----  --------  ----------------------------  --------------------------  ----------------"
    foreach ($entry in @(@{Port=$DefaultPort; Role='Chat'},
                         @{Port=9121; Role='Free'},
                         @{Port=$EmbedPort; Role='Embed'})) {

        $proc = Get-ProcessByPort -Port $entry.Port
        $health = Test-Health -Port $entry.Port
        $portOpen = Test-PortOpen -Port $entry.Port

        $modelName = if (-not $proc) { '-' }
                    elseif ($entry.Port -eq $EmbedPort) { 'snowflake-arctic-embed' }
                    else { $m = Get-CurrentModelName; if ($m) { $m.name } else { '-' } }

        $identity = if ($proc -and $health) {
            $pp = Get-ProcessModelArg -ProcessId $proc.Id
            $rf = if ($entry.Port -eq $EmbedPort) { Split-Path $EmbedModelPath -Leaf }
                  else { $m = Get-CurrentModelName; if ($m) { $m.file } else { '' } }
            $alias = if ($entry.Port -eq $EmbedPort) { 'snowflake-arctic-embed-long' }
                     else { $m2 = Get-CurrentModelName; if ($m2) { $m2.name } else { '' } }
            $class = Classify-Identity -RegistryFile $rf -ProcessPath $pp -HealthModel $health.model -ExpectedAlias $alias
            $class.state
        } elseif ($proc) { 'NO_HEALTH' } else { '-' }

        $status = if ($proc) { 'RUNNING' } elseif ($portOpen) { 'PORT_OPEN' } else { 'OFF' }

        Write-Host ("  {0,-4} {1,-8} {2,-28} {3,-26} {4,-16}" -f $entry.Port, $entry.Role, $modelName, $identity, $status)
    }
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Cyan
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

switch ($Command) {
    'list'         { Invoke-List }
    'status'       { Invoke-Status }
    'switch'       { Invoke-Switch -Name $ModelName }
    'start'        { Invoke-Switch -Name $ModelName }
    'stop'         { Invoke-Stop }
    'embed-start'  { Invoke-EmbedStart }
    'embed-stop'   { Invoke-EmbedStop }
    'embed-status' { Invoke-EmbedStatus }
    'diagnose'     { Invoke-Diagnose }
    default        { Invoke-Status }
}
