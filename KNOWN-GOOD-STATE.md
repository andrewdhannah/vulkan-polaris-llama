# Known-Good State

> Verified working configuration for llama.cpp Vulkan inference on
> Big Pickle. Update this table whenever the setup changes.

| Field | Value | Source / How Verified | Confidence |
|-------|-------|----------------------|------------|
| **GPU** | AMD Radeon RX 570 (Polaris 20, gfx803) | Windows Device Manager, `clinfo` | Confirmed |
| **VRAM** | 4 GB | GPU-Z, `clinfo` | Confirmed |
| **Driver** | AMD Adrenalin 26.5.2 (Vega/Polaris driver) | AMD Software version string | Confirmed |
| **OS** | Windows 10.0.19045 | `winver` | Confirmed |
| **Vulkan SDK** | 1.3.296.0 | `vulkaninfo` | Confirmed |
| **CPU** | Intel i5-3570K (Ivy Bridge, no AVX2/FMA) | Task Manager, CPU-Z | Confirmed |
| **llama.cpp commit** | UNKNOWN — fill after checking Big Pickle | `git rev-parse HEAD` in llama.cpp checkout | — |
| **Model path/name** | `qwen2.5-coder-1.5b-q8_0.gguf` | Server startup log, filename on disk | Confirmed |
| **Quantization** | Q8_0 | Model filename | Confirmed |
| **Context size** | 32,768 tokens | `-c 32768` flag | Confirmed |
| **GPU layers** | 99 (`-ngl 99`, saturates to 29/29) | Server startup log | Confirmed |
| **Command used** | `llama-server-mini -m qwen2.5-coder-1.5b-q8_0.gguf -p 8080 -c 32768 -ngl 99 -n 512` | Shell history, README | Confirmed |
| **Generation benchmark** | ~71.6 tok/s (GPU) | `llama-bench` or timed curl + token count | Confirmed |
| **Prompt eval benchmark** | ~3.0 tok/s | Same measurement | Confirmed |
| **CPU-only baseline** | ~6.6 tok/s | Same measurement, `-ngl 0` | Confirmed |
| **Server port** | 8080 | `-p 8080` flag | Confirmed |
| **LAN IP** | 192.168.0.158 | `ipconfig`, verified via LAN curl from Mac | Confirmed |

## How to Refresh

After any hardware, driver, or llama.cpp version change:

1. Run a `vulkaninfo` to confirm Vulkan SDK is reachable and the Polaris GPU enumerates.
2. Build with `-DGGML_VULKAN=ON` and the patch applied.
3. Run the diagnostic tests in `tests/` to confirm queue-family and pNext handling.
4. Load the known-good model and run a chat completion.
5. Benchmark generation speed.
6. Update this table.

See [REBUILD-STEPS.md](REBUILD-STEPS.md) for the full procedure.
