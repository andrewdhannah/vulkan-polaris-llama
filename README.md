# Vulkan Polaris Fix — llama.cpp on AMD RX 400/500 (gfx803)

> Making llama.cpp work on AMD Polaris GPUs via Vulkan on Windows, with a built-in HTTP server for remote access.

## The Problem

On AMD Polaris-family GPUs (RX 400/500 series, gfx803), llama.cpp's Vulkan backend fails with `VK_ERROR_DEVICE_LOST` during `vkCreateDevice`.

**Three interacting root causes were identified:**

| # | Issue | The Fix |
|---|-------|---------|
| 1 | **Two non-graphics queue families** (QF 1 + QF 2) crash Polaris driver | Fall back to single QF 0 (graphics-capable) |
| 2 | **Extra pNext feature structs** (subgroup/maint4/pep) trigger DEVICE_LOST | Use Vk11 + Vk12 only for device creation |
| 3 | **vulkan.hpp C++ wrapper** fails silently on this driver | Use pure C API (`vkCreateDevice`) |

[Full root cause analysis →](docs/root-cause.md)

## Quick Start

**On Windows, double-click:** `start_server.bat`

This starts the server with the Qwen 1.5B model on port 8080.
Wait ~12s for the model to load, then access it from any device on your network.

### From another machine

```bash
curl http://192.168.0.158:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello in 5 words"}],"stream":false}'
```

Or add it as a custom OpenAI-compatible provider in OpenWork/OpenCode:
**Settings → AI Providers → Add Custom → Base URL: `http://192.168.0.158:8080/v1`**

## Performance

Radeon RX 570 (4GB) with **Qwen 2.5 Coder 1.5B Q8_0**:

| Metric | CPU only (i5-3570K) | Vulkan GPU |
|--------|--------------------|------------|
| Generation | 6.6 tok/s | **71.6 tok/s** |
| Prompt eval | — | 3.0 tok/s |
| Layers offloaded | 0/29 | 29/29 (~1.6 GB VRAM) |

**10x speedup over CPU** on a CPU without AVX2/FMA.

## What's Included

| Path | Description |
|------|-------------|
| `patches/ggml-vulkan-polaris-fix.patch` | The actual diff to apply to llama.cpp |
| `server/server-mini.cpp` | Lightweight C++ HTTP server embedding llama.cpp |
| `server/CMakeLists.txt` | Build integration for the server |
| `start_server.bat` | One-click launcher for Windows |
| `tests/` | Standalone diagnostic programs that isolated each root cause |
| `docs/root-cause.md` | Detailed root cause analysis with evidence |
| `docs/server-setup.md` | Server usage and build instructions |

## Applying the Fix

```bash
cd /path/to/llama.cpp
git apply /path/to/vulkan-polaris-llama/patches/ggml-vulkan-polaris-fix.patch
```

Then build normally with `-DGGML_VULKAN=ON`.

## Reproducing

Tested on:
- **GPU**: AMD Radeon RX 570 (Polaris 20, gfx803)
- **Driver**: AMD Adrenalin 26.5.2 (Vega/Polaris driver)
- **OS**: Windows 10.0.19045
- **Vulkan SDK**: 1.3.296.0
- **CPU**: Intel i5-3570K (Ivy Bridge, no AVX2/FMA)

Likely affects all Polaris GPUs (RX 460–590) on Windows.

## License

MIT — same as [llama.cpp](https://github.com/ggerganov/llama.cpp).
