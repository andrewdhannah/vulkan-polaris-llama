# Librarian Knowledge Base

> **Purpose:** Everything a future instance needs to understand, maintain, and troubleshoot this llama.cpp deployment.
> **Generated:** 2026-06-12 by OpenWork session CUST-INF1 (Pass 4)
> **Repo:** `G:\llama.cpp` — HEAD `7c158fb`

---

## Table of Contents

1. [System Context](#1-system-context)
2. [Identity Architecture](#2-identity-architecture)
3. [Files & Their Roles](#3-files--their-roles)
4. [Build System](#4-build-system)
5. [Vulkan / Polaris Fix](#5-vulkan--polaris-fix)
6. [Hard-Won Lessons](#6-hard-won-lessons)
7. [Troubleshooting Guide](#7-troubleshooting-guide)
8. [Known Issues](#8-known-issues)
9. [Detailed Git State](#9-detailed-git-state)
10. [Next Improvements](#10-next-improvements)

---

## 1. System Context

| Property | Value |
|----------|-------|
| **Host OS** | Windows 10 Pro for Workstations (10.0.19045) |
| **GPU** | AMD Radeon RX 570 Series (4 GB VRAM, Polaris architecture) |
| **Driver** | AMD 31.0.21925.1001 (Windows native, not AMDVLK) |
| **Vulkan SDK** | 1.3.296.0 |
| **Compiler** | Visual Studio 2022 BuildTools (MSVC 14.44) |
| **Shell** | Windows PowerShell 5.1 |
| **Disk G: free** | ~140 GB |
| **Ports used** | 9120 (chat), 9121 (free), 9122 (embed) |
| **Temp dir** | `G:\temp\` — PID files, stderr logs |
| **Binary** | `G:\llama.cpp\build_vs\bin\Release\llama-server-mini.exe` (49.1 MB) |

### Hardware constraint: Radeon RX 570 (Polaris)

This GPU has a critical quirk: it only supports a **single command queue** (`QF 0`). Newer AMD GPUs (RDNA, RDNA2+) support multiple queues. Without the Polaris fix, `llama-server-mini.exe` crashes on startup with Vulkan errors.

---

## 2. Identity Architecture

### The Clean Rule (three-layer identity verification)

```
   ┌──────────────────────────────────────────────────────┐
   │  MANAGER (model_manager.ps1)                          │
   │  Owns the intended identity                           │
   │  Passes --alias phi-4 on start                        │
   │  This is the SOURCE OF TRUTH                          │
   └──────────────┬───────────────────────────────────────┘
                  │ --alias "phi-4"
                  ▼
   ┌──────────────────────────────────────────────────────┐
   │  SERVER (llama-server-mini.exe)                       │
   │  Confirms the active identity                         │
   │  Returns alias in /health, /v1/models, chat completions│
   │  Fallback: GGUF filename stem (deterministic)         │
   └──────────────┬───────────────────────────────────────┘
                  │ GET /health → {"model":"phi-4"}
                  ▼
   ┌──────────────────────────────────────────────────────┐
   │  DIAGNOSE (Classify-Identity)                         │
   │  Compares all three sources:                          │
   │    • Registry file (manager's model entry)            │
   │    • Process -m arg (what's loaded)                   │
   │    • Health model field (what server reports)         │
   │  Returns VERIFIED if alias matches                    │
   └──────────────────────────────────────────────────────┘
```

### What was the problem?

Before this session, `server-mini.cpp` had **three hardcoded instances** of `"qwen2.5-coder-1.5b-q8_0"`:
- `/v1/models` endpoint (line 409 originally)
- `/health` endpoint (line 421 originally)
- `/v1/chat/completions` endpoint (line 557 originally)

These were compile-time string literals. No matter what model you loaded, the server always reported itself as `qwen2.5-coder-1.5b-q8_0`. This is the "identity drift" problem documented in upstream [llama.cpp issue #11069](https://github.com/ggml-org/llama.cpp/issues/11069) and [#10056](https://github.com/ggml-org/llama.cpp/issues/10056).

### How was it fixed?

**Backported `--alias` flag to `server-mini.cpp`** (the full `examples/server/` with `--alias` didn't exist at this commit). Changes:

| Change | Lines | Purpose |
|--------|-------|---------|
| `static std::string g_alias;` | +1 | Global alias variable |
| `--alias` in `print_usage` | +1 | Documentation in help text |
| `--alias` arg parsing (`strcmp(argv[i], "--alias")`) | +2 | CLI parameter |
| Fallback computation (path→filename→stem) | +6 | Deterministic default |
| Startup message `[server] Starting (alias: ...)` | +1 | Visible confirmation |
| `/v1/models` uses `g_alias` | ~2 | Dynamic identity |
| `/health` uses `g_alias` | ~2 | Dynamic identity |
| `/v1/chat/completions` uses `g_alias` | ~2 | Dynamic identity |

**Fallback rule** (when `--alias` is not passed):
```
G:\llama.cpp\models\microsoft_Phi-4-mini-instruct-Q4_K_M.gguf
  → find last "/\" → "microsoft_Phi-4-mini-instruct-Q4_K_M.gguf"
  → find last "."  → "microsoft_Phi-4-mini-instruct-Q4_K_M"
```

This is deterministic — the same GGUF file always produces the same fallback alias.

### Manager script's role

`model_manager.ps1` passes the intended alias on every start:

**Chat:** `--alias "$($model.name)"` → e.g. `--alias "phi-4"`
**Embed:** `--alias "snowflake-arctic-embed-long"`

The `Classify-Identity` function accepts an `-ExpectedAlias` parameter. If `$HealthModel -eq $ExpectedAlias`, it returns `VERIFIED` immediately. This makes the manager's intended name the **source of truth**, not the filename.

---

## 3. Files & Their Roles

### Source files we modified

| File | Role | Notes |
|------|------|-------|
| `examples/server-mini/server-mini.cpp` | HTTP server source | `--alias` flag backported here |
| `ggml/src/ggml-vulkan/ggml-vulkan.cpp` | Vulkan backend | Polaris QF 0 fix (+57/-24 lines) |
| `.gitignore` | Git ignore rules | Server-mini artifact patterns tightened |

### Manager and tools

| File | Role | Notes |
|------|------|-------|
| `model_manager.ps1` | Process lifecycle + identity | All 8 hardening features + alias awareness |
| `_validate.ps1` | Validation script | Pre-existing, never examined |
| `G:\OpenWork\runtime_repair_receipt.md` | Change log | Outside repo, full session receipts |

### Build artifacts

| File | Role | Notes |
|------|------|-------|
| `build_vs/bin/Release/llama-server-mini.exe` | Compiled binary | 49.1 MB, rebuilt 2026-06-12 |
| `build_vs/examples/server-mini/llama-server-mini.vcxproj*` | MSBuild project | Generated by CMake |
| `build_vs/server-mini_build.log` | Build log | Previous build attempts |

### Target models

| Name | Display Name | File | Size |
|------|-------------|------|------|
| `phi-4` | Phi-4-mini 3.8B Q4_K_M | `microsoft_Phi-4-mini-instruct-Q4_K_M.gguf` | 2.32 GB |
| `llama-3.2` | Llama 3.2 3B Q5_K_M | `Llama-3.2-3B-Instruct-Q5_K_M.gguf` | 2.16 GB |
| `gemma-3` | Gemma 3 4B Q4_K_M | `gemma-3-4b-it-Q4_K_M.gguf` | 2.32 GB |
| `qwen3` | Qwen3 4B Q4_K_M | `Qwen_Qwen3-4B-Q4_K_M.gguf` | 2.33 GB |
| *(embed)* | snowflake-arctic-embed-m-long | `snowflake-arctic-embed-m-long-Q4_0.gguf` | 0.08 GB |

---

## 4. Build System

### Prerequisites

- **Visual Studio 2022 BuildTools** (or full VS 2022) with C++ workload
- **Vulkan SDK 1.3.296.0** (or later) — installed at `C:\VulkanSDK\1.3.296.0\`
- **CMake** — included in VS BuildTools
- **No OpenSSL** — HTTPS support is disabled (warning is harmless)

### Build commands

```powershell
# Full rebuild from scratch
cd G:\llama.cpp\build_vs
cmake .. -DGGML_VULKAN=ON -DLLAMA_CUDA=OFF
cmake --build . --target llama-server-mini --config Release

# Incremental rebuild (after source changes only)
cd G:\llama.cpp\build_vs
cmake --build . --target llama-server-mini --config Release
```

**Important:** Before rebuilding, kill any running `llama-server-mini.exe` process. Otherwise the linker fails with `LNK1104: cannot open file 'llama-server-mini.exe'` because the old binary is locked.

```powershell
Get-Process -Name llama-server-mini -ErrorAction SilentlyContinue | Stop-Process -Force
```

### CMake configuration notes

- **Generator:** MSBuild (Visual Studio 17 2022)
- **Platform:** x64 (auto-detected)
- **Vulkan:** Found at SDK path; shaders are compiled at build time by `vulkan-shaders-gen.exe`
- **Backends:** CPU + Vulkan (no CUDA, no SYCL)
- **OpenMP:** Enabled (found v2.0)
- **ccache:** Not found — builds are slightly slower without it

### Build time

| Scenario | Time |
|----------|------|
| Clean build (all deps + server) | ~10-12 minutes |
| Incremental (source change only) | ~3-5 minutes |
| Re-link only (no source change) | ~30 seconds |

---

## 5. Vulkan / Polaris Fix

### The Problem

Radeon RX 570 (Polaris architecture) hangs or crashes at `load_tensors` with:
```
ggml_vulkan: using 2 queues (QF 0, QF 0)
```
or similar multi-queue initialization. Polaris GPUs only support a **single command queue** (`QF 0`). The Vulkan backend was trying to use multiple queues.

### The Fix

Applied to `ggml/src/ggml-vulkan/ggml-vulkan.cpp` **(+57/-24 lines)**. Source: [github.com/yourbuddymoony/vulkan-polaris-llama](https://github.com/yourbuddymoony/vulkan-polaris-llama).

Key change: When device properties report only 1 queue family, the backend uses a single queue with `=== Using C API device (QF 0) ===`. The fix detects Polaris devices and falls back to single-queue mode.

**Verification:** On successful startup you see:
```
ggml_vulkan: using single QF 0 queue for Polaris compatibility
=== Using C API device (QF 0) ===
```

### What NOT to do

- **Do NOT** revert or modify this file unless upgrading to a newer llama.cpp version that has native Polaris support
- **Do NOT** try to use `GGML_CUDA=ON` — this system has no NVIDIA GPU
- **Do NOT** delete the Vulkan shader cache at `%USERPROFILE%\.cache\ggml\vulkan` — this is normal and speeds up subsequent loads from ~90s to ~6s

---

## 6. Hard-Won Lessons

### Lesson 1: PowerShell stream redirection causes deadlock

**The problem:** Using `ProcessStartInfo.RedirectStandardOutput = $true` with `$psi.UseShellExecute = $false` creates a 4 KB pipe buffer. Once the child process fills that buffer (which `llama-server-mini.exe` does quickly with verbose Vulkan shader output), the child **blocks** waiting for the parent to read. The parent is also blocked waiting for the child to finish/respond on the port. **Deadlock.**

**The fix:** Do NOT redirect stdout/stderr:
```powershell
$psi.RedirectStandardOutput = $false
$psi.RedirectStandardError = $false
```
Instead, let the server write directly to its own console. To capture logs, use the server's own logging (or redirect at the shell level).

**Symptoms of this deadlock:** Server process launches (PID visible), port never opens, process stays alive indefinitely but never responds to health checks. No output captured in log files. Process hangs until killed.

### Lesson 2: Health identity drift is a compile-time problem, not runtime

The `/health` endpoint's `model` field is not auto-detected from the loaded GGUF file. It's whatever was passed via `--alias` (or hardcoded as a default). This is confirmed by upstream llama.cpp issues #11069 and #10056.

**Implication:** You cannot trust `/health/model` to tell you what model is loaded unless you explicitly set `--alias`. The fix was to backport `--alias` support to the mini server.

### Lesson 3: The full `examples/server/` doesn't exist at this commit

This commit (`7c158fb`) predates the full-featured `llama-server` in the `examples/server/` directory. Only `examples/server-mini/` exists with basic HTTP + chat completions. This means:

- No `--embedding` flag (so embedding server role fails)
- No `--api-key` auth
- No `--host` binding
- No `--ssl` or HTTPS
- No `get_header_value()` or `check_auth()` middleware

If any of these are needed, the solution is to either:
1. Cherry-pick the full server from a newer commit
2. Backport the needed features one at a time

### Lesson 4: gitignore'ing a directory ignores its source too

We initially added `/examples/server-mini/` to `.gitignore` thinking it would only ignore build artifacts. **This also ignores `server-mini.cpp`** — git then treats any edits to it as irrelevant.

**Fix:** Instead of ignoring the whole directory, ignore specific artifact patterns:
```
/examples/server-mini/*.exe
/examples/server-mini/*.obj
/examples/server-mini/*.pdb
/examples/server-mini/*.ilk
/examples/server-mini/*.exp
/examples/server-mini/*.lib
```

### Lesson 5: Linker error LNK1104 means the old binary is still running

If `cmake --build` fails with `LNK1104: cannot open file 'llama-server-mini.exe'`, it's because the old process holds a file lock. Kill it first, then rebuild.

### Lesson 6: Cold vs. warm Vulkan shader cache

- **Cold start** (first load after driver update or new shader version): ~90 seconds. Vulkan compiles all shaders.
- **Warm start** (subsequent loads with cached shaders): ~6 seconds. Shader cache at `%USERPROFILE%\.cache\ggml\vulkan` eliminates recompilation.

### Lesson 7: PowerShell 5.1 compatibility constraints

The manager script must run on Windows 10's built-in PowerShell 5.1 (no PowerShell 7 assumed). Key differences from modern PowerShell:

- No `?` null-conditional operator — use `if ($x) { $x.Property }`
- No ternary `a ? b : c` — use `if/else` or `@{}` lookup
- `Get-CimInstance` preferred, but fall back to `Get-WmiObject` (deprecated in PS7 but still available in PS5.1)
- `ConvertTo-Json` has depth issues — use `-Compress` for compact output, and be aware deep objects get truncated
- `Select-String` uses `-SimpleMatch` not `-LiteralPath` for simple substring search
- No `&&`/`||` operators — use `; if ($?) { ... }`

### Lesson 8: The identity three-source comparison

The `Classify-Identity` function compares three sources, none of which is inherently authoritative:

| Source | What it contains | Risk |
|--------|-----------------|------|
| Registry file (model lookup) | The expected GGUF filename from `$Models` | Can be stale if `$Models` not updated |
| Process `-m` argument | The actual GGUF path being served | Can be stale if process restarted manually |
| Health `/model` field | What server *thinks* it is | Can be wrong if no `--alias` set |

The solution: make the **manager** authoritative by passing `-ExpectedAlias`, and have the classifier check that first. If `$HealthModel -eq $ExpectedAlias`, the identity is VERIFIED regardless of filename patterns.

---

## 7. Troubleshooting Guide

### Server won't start

**Check pre-flight:**
```powershell
.\model_manager.ps1 diagnose
```
Look for: binary exists, model exists, port free, GPU detected.

**Common causes:**
1. **Port conflict** — another process on 9120/9122. Use `Test-PortConflict` or `netstat -ano | findstr :9120`
2. **Binary missing** — rebuild needed
3. **Model file missing** — verify path in `$Models` table
4. **Vulkan crash on Polaris** — check startup output for queue errors. Polaris fix should be in `ggml-vulkan.cpp`

### Linker error LNK1104

```powershell
# Kill old process
Get-Process -Name llama-server-mini -ErrorAction SilentlyContinue | Stop-Process -Force

# Rebuild
cmake --build build_vs --target llama-server-mini --config Release
```

### Identity shows HEALTH_IDENTITY_DRIFT

The server's `/health` model field doesn't match the expected filename pattern. This means either:
- The server was started without `--alias` (or with a wrong `--alias`)
- The expected model file name in `$Models` was changed

**Fix:** Restart with the correct `--alias`. The manager script now passes it automatically.

### Identity shows UNTRUSTED_RUNTIME

None of the three sources match. This usually means the process running on the port isn't a llama-server-mini at all, or was started manually with completely different arguments.

**Fix:** Stop the rogue process: `.\model_manager.ps1 stop`

### Embedding shows EMBEDDING_ROLE_FAILED

The `llama-server-mini.exe` binary does NOT support the `--embedding` flag. It can start and serve `/health`, but `POST /v1/embeddings` returns an error or empty data.

**Root cause:** `examples/server-mini/server-mini.cpp` has no embedding endpoint handler. The full `llama-server.exe` from upstream would have it.

**Workaround:** None currently. The server runs but cannot serve embeddings.

### Server starts but port stays CLOSED

Check stderr log at `G:\temp\llama_<name>_err.txt`. The most common cause is the Vulkan shader crash on Polaris without the fix — the process crashes before opening the port.

### Build fails: "Vulkan SDK not found"

Ensure Vulkan SDK 1.3.296.0 is installed at `C:\VulkanSDK\1.3.296.0\`. Check `VULKAN_SDK` environment variable. If using a different path, update `CMAKE_PREFIX_PATH`.

### File is gitignored when it shouldn't be

```powershell
# Check if git is ignoring a file
git check-ignore -v <filepath>

# Check what rule is responsible
# The output shows which .gitignore line and pattern matched
```

---

## 8. Known Issues

| # | Issue | Cause | Impact | Workaround |
|---|-------|-------|--------|------------|
| 1 | **No embedding support** | `server-mini.cpp` lacks `/v1/embeddings` handler | Embedding server role non-functional | Build full `llama-server.exe` from upstream |
| 2 | **No TLS/HTTPS** | OpenSSL not found during CMake config | All traffic plaintext | Tunnel via SSH or VPN |
| 3 | **Console window visible** | `ProcessWindowStyle::Hidden` not fully suppressing | Minor cosmetic issue | Start via Windows Scheduled Task with no window |
| 4 | **No `--api-key` auth** | Mini server lacks auth middleware | Anyone on LAN can query | Firewall port restriction |
| 5 | **No `--host` binding** | Mini server binds `0.0.0.0` always | Cannot restrict to localhost only | Firewall rule |
| 6 | **CRLF warnings in git** | Windows git conversion | Cosmetic only in `git status` | Set `core.autocrlf` or ignore |
| 7 | **No multi-model serving** | Single model per process | Must stop/start to switch models | Inherent to mini server design |

---

## 9. Detailed Git State

### Committed (HEAD `7c158fb`)

The base commit from upstream llama.cpp. This is a snapshot that has:
- `examples/server-mini/server-mini.cpp` — **NOT in HEAD** (was added to working tree as part of dirty state)
- `examples/server-mini/CMakeLists.txt` — **NOT in HEAD** (same)
- No `model_manager.ps1` — created from scratch
- No `.gitignore` additions — all ours

### Dirty state we carry

All modifications are additive or isolated — no tracked files were overwritten with conflicting content:

| File | Change | Origin |
|------|--------|--------|
| `.gitignore` | + artifact patterns + server-mini rules | Our work |
| `README.md` | CRLF normalization | Pre-existing (git smudge) |
| `examples/CMakeLists.txt` | Added `server-mini` subdirectory | Pre-existing dirty state |
| `ggml/src/ggml-vulkan/ggml-vulkan.cpp` | Polaris QF 0 fix (+57/-24) | Pre-existing dirty state |

### Untracked files

| File | Purpose |
|------|---------|
| `examples/server-mini/` | Directory not in HEAD (source + CMakeLists.txt added by dirty state) |
| `model_manager.ps1` | Manager script (new) |
| `_validate.ps1` | Validation script (pre-existing) |
| `LIBRARIAN_KNOWLEDGE.md` | This file (new) |

### What to commit on next meaningful change

The files that represent our systemic changes (not build outputs):

```
git add examples/server-mini/server-mini.cpp
git add model_manager.ps1
git add .gitignore
git add LIBRARIAN_KNOWLEDGE.md
git commit -m "feat: backport --alias flag to llama-server-mini + identity manager"
```

If incorporating pre-existing dirty state:
```
git add examples/CMakeLists.txt
git add ggml/src/ggml-vulkan/ggml-vulkan.cpp
git add README.md
```

---

## 10. Next Improvements

### Priority: Embedding support

The single biggest gap is the missing `/v1/embeddings` endpoint. Two approaches:

1. **Backport embedding handler** to `server-mini.cpp` — ~100 lines of C++ to add the endpoint
2. **Cherry-pick full `llama-server.exe`** from a newer llama.cpp commit — requires merging `examples/server/` directory and its CMakeLists.txt

### Medium priority: Security

- Add `--api-key` support to mini server (simple token check middleware)
- Add `--host` binding for localhost-only (currently binds `0.0.0.0`)
- Add TLS support (requires OpenSSL or build `llama-server` with HTTPS)

### Low priority: Quality of life

- Fully suppress the console window on start
- Add auto-restart on crash to manager script
- Add context length auto-detection from GGUF metadata
- Add `/v1/models` support for multiple running servers
- Add performance benchmark command to manager

---

*Generated by OpenWork session CUST-INF1 (Pass 4) — 2026-06-12*
*Purpose: Ensure future instances can start with full context of all hard-won knowledge*
