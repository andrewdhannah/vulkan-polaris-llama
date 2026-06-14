# Troubleshooting: Windows llama.cpp Runtime

> **Survival guide for future sessions.**  
> If something is broken, start here.

---

## First Command to Run

```powershell
cd G:\llama.cpp
.\model_manager.ps1 diagnose
```

This gives you: binary status, model files, ports/processes, GPU detection, identity verification, PID file consistency, disk space. Read the output carefully before doing anything else.

---

## Server Won't Start

### If `diagnose` shows pre-flight failures:

| Check | If failing | Fix |
|-------|-----------|-----|
| Binary exists | "MISSING" | Rebuild: `cmake --build build_vs --target llama-server-mini --config Release` |
| Model file exists | "MISSING" | Download the GGUF or update `$Models` in `model_manager.ps1` |
| Port is free | "CONFLICT" | Identify the owner with `Get-NetTCPConnection -LocalPort 9120`. Stop or kill the conflicting process. |
| GPU detected | "No AMD/Radeon" | Check AMD driver is installed. Run `vulkaninfo` to confirm Vulkan works. |

### If `diagnose` passes but start hangs:

The server process might have launched but hit a Vulkan crash. Check:

```powershell
Get-Content G:\temp\llama_<model>_err.txt -Tail 20
```

Common causes:

1. **Polaris Vulkan crash** — Look for `=== Using C API device (QF 0) ===` in logs. If missing, the Polaris fix in `ggml-vulkan.cpp` was reverted or the binary wasn't rebuilt after the fix.
2. **Out of VRAM** — The RX 570 has 4 GB. Models over ~2.5 GB GGUF may exceed VRAM + KV cache. Try `-ngl 99` with a smaller model or reduce context with `-c 2048`.
3. **Shader compilation crash** — Delete `%USERPROFILE%\.cache\ggml\vulkan\*` and retry (forces cold compilation). A cold start takes ~90s.

---

## Port Is Occupied

```powershell
# Find what's on port 9120
netstat -ano | findstr :9120

# If it's a stale llama-server-mini
Get-Process -Id <PID> -ErrorAction SilentlyContinue | Stop-Process -Force

# If it's something else (e.g. nginx, docker)
# Resolve manually or change the port in model_manager.ps1
```

---

## GPU / Vulkan Not Detected

```powershell
# Check Vulkan installation
vulkaninfo | findstr "Vulkan Instance"

# List physical devices
vulkaninfo | findstr "deviceName"

# Check AMD driver
Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like "*Radeon*" }
```

If Vulkan SDK is missing, install from https://vulkan.lunarg.com/ (use same version: 1.3.296.0).

---

## Identity Shows Stale `qwen2.5-coder-1.5b-q8_0`

**Meaning:** The server was built before the `--alias` patch was applied.

**Fix:** Rebuild `llama-server-mini.exe` from the current source:

```powershell
Get-Process -Name llama-server-mini -ErrorAction SilentlyContinue | Stop-Process -Force
cmake --build build_vs --target llama-server-mini --config Release
```

Then restart with `model_manager.ps1`. The new binary will read `--alias` and return the correct model name.

If the problem persists, check that `examples/server-mini/server-mini.cpp` contains `g_alias` references (should show 8 matches):

```powershell
git grep -c "g_alias" -- examples/server-mini/server-mini.cpp
```

---

## `/health` and Manager Disagree

If `status` shows `HEALTH_IDENTITY_DRIFT`:

1. **Check launch args** — Is `--alias` being passed? Verify in `status` output under "Process:".
2. **Check manager's $Models** — Does the model's `name` field match what you expect?
3. **Restart** — `.\model_manager.ps1 stop; .\model_manager.ps1 start <name>`
4. **If still drifts** — Run `diagnose` and look at the identity classification line for details.

---

## PID File Exists But Process Is Gone

This is a stale PID file. The manager should auto-clean it on next `start`. To manually clean:

```powershell
Remove-Item "G:\temp\llama_manager_9120.pid" -Force
```

Or run `.\model_manager.ps1 stop` (which calls `Remove-PidFile`).

---

## Process Exists But PID File Is Gone

The server is running but manager doesn't "own" it. This happens if the server was started manually, by a different script, or from a previous session.

**Fix:** Stop it and restart via the manager:

```powershell
Get-Process -Name llama-server-mini -ErrorAction SilentlyContinue | Stop-Process -Force
.\model_manager.ps1 start phi-4
```

---

## Model Path Is Wrong

The manager has a `$Models` table with `file` fields. Each `start` or `switch` command looks up the model by name and joins with `$ModelsDir`.

If a model can't be found:

```powershell
# Check the expected path
Write-Host "$(Join-Path (Split-Path (Get-Item .).FullName) models)\microsoft_Phi-4-mini-instruct-Q4_K_M.gguf"

# List actual files
Get-ChildItem G:\llama.cpp\models\*.gguf | Select-Object Name
```

Update the `file` field in `$Models` if needed.

---

## Context Is Full / `[context full]` Response

The mini server accumulates conversation history in RAM. Once the KV cache fills (4096 tokens by default), it returns `[context full]`.

### Option A: Use the `/reset` endpoint (fastest)

```powershell
# Reset context without restarting the server
Invoke-RestMethod -Uri "http://localhost:9120/reset" -Method Post
# → {"status":"ok","message":"context reset"}
```

### Option B: Restart the server

```powershell
.\model_manager.ps1 stop
.\model_manager.ps1 start phi-4
```

### Option C: Use the Rust router (recommended for multiple sessions)

The router automatically manages context per session. When switching sessions, it calls `/reset` on llama.cpp and repacks the new session's history.

```powershell
# Start router (listens on port 8080)
.\router\target\release\llama-router.exe

# Use router instead of direct llama.cpp
curl http://localhost:8080/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "X-Librarian-Session: session-1" `
  -d '{"messages":[{"role":"user","content":"Hello"}]}'
```

---

## Router Issues

### Router won't start

```powershell
# Check if port 8080 is in use
Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue

# Check if llama.cpp is running on port 9120
Invoke-RestMethod -Uri "http://127.0.0.1:9120/health"
```

### Router returns 502 Bad Gateway

The router can't reach llama.cpp. Ensure:
1. `llama-server-mini.exe` is running on port 9120
2. It's bound to `127.0.0.1` (not just localhost name resolution)
3. No firewall is blocking loopback traffic

### Session state lost after router restart

The router stores sessions in RAM only. Restarting the router clears all sessions. SQLite persistence is planned for a future update.

---

## Inference Works But Prompt Following Fails

**This is a model capability issue, not a runtime issue.**

A weak or quantized model can fail exact-instruction obedience while the runtime lane still passes (server starts, endpoints respond, tokens generate). This is expected behavior.

**The three independent axes:**
1. **Runtime pass** — Server starts, endpoints respond, identity correct, lifecycle clean
2. **Instruction-following pass** — Model obeys system prompt, follows format, respects constraints
3. **Manager lifecycle pass** — Ports, PIDs, errors, state transitions

A model that passes 1 and 3 but fails 2 needs a stronger model, not a runtime fix.

---

## Git Status Is Noisy

The repo tracks the upstream `llama.cpp` project plus our modifications. Some files have CRLF noise due to line-ending conversion on Windows:

```powershell
# Suppress CRLF warnings
git config core.autocrlf true
```

Our permanent changes (in git HEAD) are:

| File | Purpose |
|------|---------|
| `examples/server-mini/server-mini.cpp` | `--alias` patch |
| `model_manager.ps1` | Manager script |
| `.gitignore` | Clean artifact rules |
| `ggml/src/ggml-vulkan/ggml-vulkan.cpp` | Polaris QF 0 fix |
| `docs/*.md` | Documentation |
| `README.md` | Operational README |

If `git status` shows untracked files like `build_vs/` or `G:\temp\` files, they are already in `.gitignore`.

---

## Quick Reference

| Symptom | First Action |
|---------|-------------|
| Anything broken | `.\model_manager.ps1 diagnose` |
| Server won't start | Check pre-flight output, check `G:\temp\llama_*_err.txt` |
| Wrong model identity | Rebuild binary (stale hardcoded default) |
| Port conflict | `netstat -ano \| findstr :<port>` |
| Embeddings not working | Known issue — mini server lacks `--embedding` |
| Stale PID file | Run `stop` or `Remove-Item` on the `.pid` file |
| Slow startup | Warm cache? First load takes ~90s, subsequent ~6s |
| Exact prompt fails | Model capability, not runtime — try a stronger model |

---

*See also: [`WINDOWS-LLAMA-MANAGER-HARDENING.md`](WINDOWS-LLAMA-MANAGER-HARDENING.md), [`LLAMA-SERVER-MINI-ALIAS-PATCH.md`](LLAMA-SERVER-MINI-ALIAS-PATCH.md), [`HANDOFF-WINDOWS-LLAMA-POC.md`](HANDOFF-WINDOWS-LLAMA-POC.md)*
