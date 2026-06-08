# Vulkan Polaris Fix — Known-Good llama.cpp Enablement for AMD RX 400/500 (gfx803)

> A compatibility patch and rebuild record for llama.cpp Vulkan inference on
> AMD Polaris GPUs, with a built-in HTTP server for LAN access, plus a full
> model benchmark suite and model manager.

**Proven on:** [Big Pickle](HARDWARE-RECEIPT.md) — a Windows 10 machine with
an AMD Radeon RX 570 4 GB and an Intel i5-3570K (no AVX2/FMA).

## Status

| Scope | Status |
|-------|--------|
| **Confirmed** | RX 570 (Polaris 20) / Windows 10 / Vulkan SDK 1.3.296.0 |
| **Expected** | RX 470/480/570/580/590 class Polaris GPUs on Windows |
| **Untested** | Linux RADV, AMD RDNA (RX 5000+), NVIDIA, Intel |

## The Problem

On AMD Polaris-family GPUs (RX 400/500 series, gfx803), llama.cpp's Vulkan
backend fails with `VK_ERROR_DEVICE_LOST` during `vkCreateDevice`.

**Three interacting root causes were identified:**

| # | Issue | The Fix |
|---|-------|---------|
| 1 | **Two non-graphics queue families** (QF 1 + QF 2) crash Polaris driver | Fall back to single QF 0 (graphics-capable) |
| 2 | **Extra pNext feature structs** (subgroup/maint4/pep) trigger DEVICE_LOST | Use Vk11 + Vk12 only for device creation |
| 3 | **vulkan.hpp C++ wrapper** fails silently on this driver | Use pure C API (`vkCreateDevice`) |

[Full root cause analysis →](docs/root-cause.md)

---

## Quick Start (on Big Pickle or equivalent)

**1. Pick a model and start the server:**

```powershell
.\workspace\model_manager.ps1 switch phi-4
```

Wait ~30s for the model to load (the script polls until it's ready).

**2. Use it from any device on your network:**

```bash
curl http://192.168.0.158:9120/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello in 5 words"}],"stream":false}'
```

**3. Or add it in OpenWork/OpenCode:**
**Settings → AI Providers → Add Custom → Base URL: `http://192.168.0.158:9120/v1`**

**4. Switch models anytime from OpenWork:**
> *"switch to phi-4"* or *"switch to llama-3.2"*
>
> The agent calls `model_manager.ps1` which stops the old server and starts the new one.

---

## Viable Models (tested on RX 570 4GB)

All 7 models below were downloaded and benchmarked. Only 4 load on the RX 570;
of those, 3 are genuinely useful.

| Rank | Model | File Size | VRAM | Speed | Multi-turn | Verdict |
|------|-------|-----------|------|-------|------------|---------|
| 🥇 | **Phi-4-mini 3.8B Q4_K_M** | 2.32 GB | ~2.5 GB | 14–51 tok/s | ✅ 4/4 turns | **Best all-rounder** |
| 🥈 | **Llama 3.2 3B Q5_K_M** | 2.16 GB | ~2.3 GB | **32–49 tok/s** | ✅ 4/4 turns | **Fastest daily driver** |
| 🥉 | **Gemma 3 4B Q4_K_M** | 2.32 GB | ~2.5 GB | 19–35 tok/s | ✅ 4/4 turns | **Most verbose/thorough** |
| 4 | Qwen3 4B Q4_K_M | 2.33 GB | ~2.5 GB | 22–40 tok/s | ❌ context full | Needs >8K context |

**Failed / not viable:**
- **Gemma 4 4B Q2_K_P** (2.80 GB) — loads but chat template incompatible
- **Qwen2.5 Coder 1.5B Q8_0** (1.76 GB) — too small, repeats, no context retention
- **Qwen MOE 2x1.5B Q4_K_M** (2.34 GB) — ruminative `<think>` loops, times out
- **Llama3-8B-BitNet TQ1_0** (2.06 GB) — Vulkan crashes on inference; CPU = 0.07 tok/s

[Full benchmark report →](workspace/benchmark_report.md)

---

## Benchmark Tests

Each model was put through 5 standardized tests:

| Test | Prompt | Max tokens | What we checked |
|------|--------|-----------|-----------------|
| **Simple QA** | "What is the capital of France and its population?" | 256 | Factual accuracy |
| **Complex Reasoning** | "Explain P vs NP. Why is it important? Example of NP-complete problem." | 1024 | Reasoning depth |
| **Code Generation** | "Write a complete Python merge sort with comments on time and space complexity." | 1024 | Code quality & completeness |
| **Math** | Train A 60 mph / Train B 40 mph / 200 miles apart — how long to meet? | 512 | Step-by-step reasoning & answer |
| **Multi-turn Context** | 4-turn conversation introducing name (Andrew), city (Toronto), job (software engineer), then asking follow-ups | 128–256 | Context retention across turns |

All viable models correctly answered the math problem (2 hours).

---

## Performance Baseline

Radeon RX 570 (4GB) with **Qwen 2.5 Coder 1.5B Q8_0** (early test):

| Metric | CPU only (i5-3570K) | Vulkan GPU |
|--------|--------------------|------------|
| Generation | 6.6 tok/s | **71.6 tok/s** |
| Prompt eval | — | 3.0 tok/s |
| Layers offloaded | 0/29 | 29/29 (~1.6 GB VRAM) |

**10x speedup over CPU** on a CPU without AVX2/FMA.

For the viable 3–4B models, the Vulkan GPU delivers **14–51 tok/s** depending
on model and prompt complexity.

---

## Model Switching (for OpenWork)

The repo includes a PowerShell model manager for seamless switching:

```powershell
.\workspace\model_manager.ps1 list            # Show all viable models
.\workspace\model_manager.ps1 status          # Check running model
.\workspace\model_manager.ps1 switch phi-4    # Switch to Phi-4-mini
.\workspace\model_manager.ps1 switch llama-3.2  # Switch to Llama 3.2
.\workspace\model_manager.ps1 switch gemma-3  # Switch to Gemma 3
.\workspace\model_manager.ps1 stop            # Stop the server
```

From OpenWork, just ask: *"switch to phi-4"*

There is also an HTML dashboard (`workspace/dashboard.html`) with live status
and one-click switching buttons — open it in a browser alongside your session.

---

## What's Included

| Path | Description |
|------|-------------|
| `patches/ggml-vulkan-polaris-fix.patch` | The actual diff to apply to llama.cpp |
| `server/server-mini.cpp` | Lightweight C++ HTTP server embedding llama.cpp |
| `server/CMakeLists.txt` | Build integration for the server |
| `start_server.bat` | One-click launcher for Windows (edit paths for your setup) |
| `workspace/` | Benchmark results, model manager, HTML dashboard, and launchers |
| `workspace/benchmark_report.md` | Full benchmark report for all 7 models |
| `workspace/model_manager.ps1` | PowerShell script to list/switch/control models (OpenWork-friendly) |
| `workspace/dashboard.html` | Visual dashboard with live status and model switching |
| `workspace/launchers/` | One-click `.bat` launchers for each individual model |
| `tests/` | Standalone diagnostic programs that isolated each root cause |
| `docs/root-cause.md` | Detailed root cause analysis with evidence |
| `docs/server-setup.md` | Server usage, build and troubleshooting guide |

## Applying the Fix

```bash
cd /path/to/llama.cpp
git apply /path/to/vulkan-polaris-llama/patches/ggml-vulkan-polaris-fix.patch
```

Then build normally with `-DGGML_VULKAN=ON`.

See [REBUILD-STEPS.md](REBUILD-STEPS.md) for the complete Windows procedure.

## Reproducing

Tested on:
- **GPU**: AMD Radeon RX 570 (Polaris 20, gfx803)
- **Driver**: AMD Adrenalin 26.5.2 (Vega/Polaris driver)
- **OS**: Windows 10.0.19045
- **Vulkan SDK**: 1.3.296.0
- **CPU**: Intel i5-3570K (Ivy Bridge, no AVX2/FMA)

Likely affects all Polaris GPUs (RX 460–590) on Windows.

## Documents

- [Hardware Receipt](HARDWARE-RECEIPT.md) — Why this repo exists and what it preserves
- [Known-Good State](KNOWN-GOOD-STATE.md) — Verified configuration table
- [Rebuild Steps](REBUILD-STEPS.md) — Complete Windows rebuild procedure
- [Security Notes](SECURITY.md) — LAN-only deployment guidance
- [Changelog](CHANGELOG.md)

## License

MIT — same as [llama.cpp](https://github.com/ggerganov/llama.cpp).
