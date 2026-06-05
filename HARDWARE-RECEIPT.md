# Hardware Receipt — Big Pickle

> A preservation record of the known-good llama.cpp Vulkan inference setup
> on AMD Polaris hardware, captured while the system is working.

## Machine Identity

| Field | Value |
|-------|-------|
| **Machine name** | Big Pickle |
| **Purpose** | Local llama.cpp Vulkan inference worker for OpenWork / local coding-model experiments |
| **GPU family** | AMD Polaris / RX 400/500 / gfx803 |
| **Confirmed GPU** | AMD Radeon RX 570 (4 GB) — Polaris 20 |
| **OS** | Windows 10.0.19045 |
| **Vulkan SDK** | 1.3.296.0 |
| **Driver** | AMD Adrenalin 26.5.2 (Vega/Polaris driver) |

## Known Failure

`VK_ERROR_DEVICE_LOST` during `vkCreateDevice` when using llama.cpp's default
Vulkan backend on Polaris. Three interacting root causes:

| # | Issue | The Fix |
|---|-------|---------|
| 1 | Two non-graphics queue families (QF 1 + QF 2) crash the Polaris driver | Fall back to graphics-capable QF 0 when initial selection fails |
| 2 | Extra pNext feature structs (subgroup size control, maintenance4, pipeline executable properties) trigger DEVICE_LOST on device creation | Use minimal Vk11 + Vk12 pNext chain for `vkCreateDevice`; full chain only for feature queries |
| 3 | vulkan.hpp C++ wrapper fails silently on this driver path | Use direct C API (`vkCreateDevice` / `VkDeviceCreateInfo`) |

## Known-Good Test

| Metric | Value |
|--------|-------|
| **Model** | Qwen 2.5 Coder 1.5B Q8_0 |
| **Layers offloaded** | 29/29 (~1.6 GB VRAM) |
| **Vulkan generation** | ~71.6 tok/s |
| **CPU baseline** (i5-3570K) | ~6.6 tok/s |
| **Speedup** | ~10× |
| **Context size** | 32,768 tokens |

## Why This Repo Exists

This repository is a **preservation record of a working state**, not merely a
generic patch submission.

The fix was discovered through systematic diagnostic testing on the actual
target hardware (Big Pickle). Each root cause was isolated with a standalone
test program before the combined patch was written. The server-mini
implementation was then built and tested on the same machine, and verified
to work over LAN from a separate development machine (Mac).

The intent is that if the working setup ever needs to be rebuilt — after a
driver update, OS reinstall, hardware swap, or llama.cpp version bump — this
receipt captures exactly what worked, on exactly what hardware, with exactly
what configuration.

## Scope

- **Confirmed**: Windows 10 / Polaris (gfx803) / AMD Adrenalin driver.
- **Expected but untested**: Other Polaris GPUs (RX 460–590) on Windows.
- **Not applicable**: Linux RADV, NVIDIA, Intel, AMD RDNA (RX 5000+).

## References

- [Known-good state table](KNOWN-GOOD-STATE.md)
- [Root cause analysis](docs/root-cause.md)
- [Rebuild steps](REBUILD-STEPS.md)
- [Server setup](docs/server-setup.md)
