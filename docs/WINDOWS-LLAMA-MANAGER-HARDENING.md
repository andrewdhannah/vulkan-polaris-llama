# Windows llama.cpp Manager Hardening

> **Date:** 2026-06-12  
> **Scope:** All 8 hardening improvements to `model_manager.ps1`, identity system, and `.gitignore` cleanup.

---

## 1. `.gitignore` Cleanup

**Problem:** The rule `/examples/server-mini/` was too broad — it gitignored the entire directory including the `server-mini.cpp` source file. Edits to the source were invisible to `git diff`.

**Fix:** Replaced with specific artifact patterns:

```gitignore
/examples/server-mini/*.exe
/examples/server-mini/*.obj
/examples/server-mini/*.pdb
/examples/server-mini/*.ilk
/examples/server-mini/*.exp
/examples/server-mini/*.lib
```

Also added patterns for runtime artifacts: Vulkan debug output, temp logs, backup files.

---

## 2. Pre-Flight Checks (`Invoke-PreFlightCheck`)

Before any launch, the function verifies:

- Binary `llama-server-mini.exe` exists at the expected path
- Model GGUF file exists
- Port is free (no other process listening)
- Vulkan GPU is detected (AMD Radeon)

If any check fails, the launch is aborted with a clear message.

---

## 3. `diagnose` Command

A comprehensive system snapshot command:

| Section | Details |
|---------|---------|
| Environment | Hostname, OS, PowerShell version, repo HEAD, disk free |
| Binary | Path, size, last modified date |
| GPU | All video controllers with VRAM and driver version |
| Ports & Processes | Per-port: listening state, PID, model argument, health response, identity classification, PID file consistency |
| Model Files | Per-model: name, file path, size (or MISSING) |
| Summary Grid | Tabular view of all ports with role, model, identity, status |

---

## 4. PID File Tracking

PID files stored at `G:\temp\llama_manager_<port>.pid`:

| Function | Purpose |
|----------|---------|
| `Write-PidFile` | Writes process ID to file on launch |
| `Read-PidFile` | Reads saved PID for a port |
| `Remove-PidFile` | Removes PID file on stop/cleanup |

---

## 5. Orphan / Stale PID Cleanup (`Invoke-StalePidCleanup`)

On `start` or `embed-start`, the script checks for an existing PID file:

1. **PID file exists, process running, port matches** → "Server already running", abort
2. **PID file exists, process gone** → Clean up stale PID file, proceed
3. **PID file exists, process running but different port** → PID was reused by another process, clean up
4. **No PID file** → Proceed normally

---

## 6. Graceful Stop Then Force Fallback (`Stop-ProcessGracefully`)

```powershell
taskkill /PID <id>       # Sends close signal (graceful)
Start-Sleep 3            # Wait for clean shutdown
if (process still alive) # Fallback
  Stop-Process -Force    # Force kill
```

This gives the server a chance to flush state before being forcefully terminated.

---

## 7. Port Conflict Detection (`Test-PortConflict`)

Before starting, checks `Get-NetTCPConnection` for the target port:

- **TimeWait state**: Ignored (kernel finishing TCP close, not a real conflict)
- **PID 0**: Ignored (phantom kernel entry)
- **Own llama-server-mini**: Ignored (we'll stop it)
- **Any other process**: Reported as conflict, launch aborted

---

## 8. Safer PowerShell Error Handling

- `$ErrorActionPreference = 'Continue'` at script top (not `Stop`)
- `try/catch` around all WMI/CIM calls (hardware queries are fragile)
- `Get-ProcessCmdLine` with CIM fallback to legacy WMI (PS5.1 compatibility)
- `try/catch` around process launch (binary might be locked or missing)
- Null checks on every function return before property access

---

## 9. Model Identity Verification (`Classify-Identity`)

Three-source comparison with alias awareness:

```powershell
function Classify-Identity {
    param(
        [string]$RegistryFile,    # Expected GGUF filename from $Models table
        [string]$ProcessPath,     # Actual -m argument from running process
        [string]$HealthModel,     # /health response model field
        [string]$ExpectedAlias    # Manager's intended alias name
    )
```

Classification states:

| State | Meaning |
|-------|---------|
| `VERIFIED` | Health alias matches `$ExpectedAlias`, or all three filename sources match |
| `HEALTH_IDENTITY_DRIFT` | Registry + process match, but health differs |
| `PROCESS_DRIFT` | Registry + health match, but process differs |
| `REGISTRY_STALE` | Process + health match, but registry differs |
| `UNTRUSTED_RUNTIME` | None of the three sources match |

---

## 10. Final `--alias` Support

The server-mini binary now accepts `--alias <name>` and reports it in all endpoints:

| Manager action | Launch argument |
|---------------|----------------|
| `start phi-4` | `--alias "phi-4"` |
| `embed-start` | `--alias "snowflake-arctic-embed-long"` |

---

## Acceptance Test Results

| Test | Result |
|------|--------|
| `GET /health` | `{"model":"phi-4"}` |
| `GET /v1/models` | `{"id":"phi-4"}` |
| `POST /v1/chat/completions` | `"model":"phi-4"` + valid inference |
| `status` command | `VERIFIED - Health alias matches expected name` |
| `diagnose` command | `VERIFIED` in summary grid |
| `stop` command | PID file removed, no orphan process |
| Final `diagnose` | All ports clean, no orphans |

---

*See also: [`LLAMA-SERVER-MINI-ALIAS-PATCH.md`](LLAMA-SERVER-MINI-ALIAS-PATCH.md), [`TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md`](TROUBLESHOOTING-WINDOWS-LLAMA-RUNTIME.md), [`HANDOFF-WINDOWS-LLAMA-POC.md`](HANDOFF-WINDOWS-LLAMA-POC.md)*
