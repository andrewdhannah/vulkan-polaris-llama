# Root Cause Analysis: Vulkan `VK_ERROR_DEVICE_LOST` on AMD Polaris GPUs

## Summary

On AMD Polaris-family GPUs (RX 400/500 series, gfx803), llama.cpp's Vulkan
backend fails with `VK_ERROR_DEVICE_LOST` during device creation. Three
independent factors conspire to trigger this AMD Windows driver bug.

**The patch in this repo** is a compatibility workaround for AMD Polaris
Windows Vulkan drivers. It is not claimed to be necessary for newer AMD
RDNA GPUs (RX 5000+), NVIDIA, Intel, or Linux RADV.

## Confirmed Environment

| Component | Value |
|-----------|-------|
| GPU | AMD Radeon RX 570 (Polaris 20, gfx803) |
| Driver | AMD Adrenalin 26.5.2 (Vega/Polaris driver) |
| OS | Windows 10.0.19045 |
| Vulkan SDK | 1.3.296.0 |
| CPU | Intel i5-3570K |

## Symptom

`VK_ERROR_DEVICE_LOST` returned by `vkCreateDevice` when llama.cpp's Vulkan
backend attempts to initialize the GPU device. The error occurs with the
default backend behavior and prevents any Vulkan-accelerated inference.

## Factor 1: Queue Family Selection

### The Bug

The llama.cpp Vulkan backend selects **two non-graphics queue families**:
- QF 1 (compute + transfer, 2 queues)
- QF 2 (compute only, 2 queues)

On Polaris, calling `vkCreateDevice` with two queue families where **neither**
has the `VK_QUEUE_GRAPHICS_BIT` causes the driver to return
`VK_ERROR_DEVICE_LOST`.

### Evidence

Systematic testing of all queue family combinations on an RX 570:

| QF Combination | Result |
|----------------|--------|
| QF 0 only (graphics + compute + transfer) | ✅ PASS |
| QF 0 + QF 1 | ✅ PASS |
| QF 0 + QF 2 | ✅ PASS |
| QF 1 only (compute + transfer) | ❌ FAIL |
| QF 2 only (compute) | ❌ FAIL |
| **QF 1 + QF 2** | **❌ FAIL** |

### The Fix

When device creation fails with the default queue selection, fall back to:
- A single queue from QF 0 (graphics-capable)
- One queue descriptor with `queueCount = 1`

This works because QF 0 on Polaris can handle compute and transfer operations
even though it has the graphics flag — the driver handles it correctly.

### Diagnostic Test

`tests/test_vk_queues.cpp` tests all queue family combinations.

## Factor 2: pNext Feature Chain

### The Bug

llama.cpp queries device features using `vkGetPhysicalDeviceFeatures2` with a
pNext chain containing:
1. `VkPhysicalDeviceVulkan11Features`
2. `VkPhysicalDeviceVulkan12Features`
3. `VkPhysicalDeviceSubgroupSizeControlFeaturesEXT`
4. `VkPhysicalDeviceMaintenance4Features`
5. `VkPhysicalDevicePipelineExecutablePropertiesFeaturesKHR`

For device creation, the same pNext chain is passed to `vkCreateDevice`.
On Polaris, including the extra structs (subgroup, maintenance4, pipeline
executable properties) triggers `VK_ERROR_DEVICE_LOST` — even with a single
QF 0 queue.

### Evidence

| pNext Chain Configuration | Result |
|---------------------------|--------|
| Vk11 + Vk12 only | ✅ PASS |
| Vk11 + Vk12 + SubgroupSizeControl | ❌ FAIL |
| Vk11 + Vk12 + Maintenance4 | ❌ FAIL |
| Vk11 + Vk12 + PipelineExecutableProps | ❌ FAIL |
| Full chain (all 5) | ❌ FAIL |

### The Fix

- **Query features** with the full pNext chain (needed for capability detection)
- **Create device** with a minimal chain: `Vk11Features → Vk12Features → nullptr`
- This preserves feature detection while avoiding the driver bug in creation

### Diagnostic Tests

- `tests/test_vk_extra_chain.cpp` — Tests pNext chain configurations
- `tests/test_vk_llamalike.cpp` — Reproduces the full llama.cpp device creation sequence

## Factor 3: vulkan.hpp C++ Wrapper

### The Bug

llama.cpp uses the vulkan.hpp C++ wrapper (`vk::DeviceCreateInfo`,
`vk::PhysicalDevice::createDevice`). On the Polaris driver, the C++ wrapper
version of device creation fails silently even when the equivalent C API call
succeeds with identical parameters.

### Evidence

Direct comparison with identical queue + feature setup:

| API | Result |
|-----|--------|
| `vk::PhysicalDevice::createDevice()` | ❌ FAIL |
| `vkCreateDevice()` + `VkDeviceCreateInfo` | ✅ PASS |

### The Fix

Use pure C API (`VkDeviceCreateInfo` / `vkCreateDevice`) for device creation.
The C++ wrapper is still used for enumeration and other operations.

### Diagnostic Test

`tests/test_vk_qf_diff.cpp` — Compares C++ wrapper vs C API with identical parameters.

## Patch Behavior

The combined patch (`patches/ggml-vulkan-polaris-fix.patch`) modifies
`ggml/src/ggml-vulkan/ggml-vulkan.cpp` to:

1. **Change queue descriptor type** from `vk::DeviceQueueCreateInfo` to
   `VkDeviceQueueCreateInfo` (C API struct).
2. **Fall back to QF 0** when the initial queue selection finds no
   graphics-capable family with available queues.
3. **Truncate the pNext chain** for device creation to Vk11 + Vk12 only.
4. **Use `vkCreateDevice`** instead of the C++ wrapper function.

All other Vulkan operations (enumeration, memory management, inference)
continue to use the C++ wrapper.

## Hardware Scope

### Confirmed

| GPU | Driver | OS | Status |
|-----|--------|----|--------|
| AMD Radeon RX 570 (Polaris 20) | Adrenalin 26.5.2 | Windows 10 | ✅ PASS |

### Likely Affected (Polaris-family, gfx803)

AMD RX 460, 470, 480, 550, 560, 570, 580, 590 — all Polaris-based GPUs
on Windows with recent AMD drivers.

### Not Affected (Different Driver Stacks)

- **NVIDIA**: Different queue family layout (usually single universal QF),
  different driver code path for pNext chains.
- **Intel ANV**: Similar to NVIDIA, single QF layout.
- **Linux RADV**: The open-source Mesa driver handles these configurations
  correctly. This is a Windows driver-specific issue.
- **AMD RDNA (RX 5000/6000/7000 series)**: Different driver stack
  (`amdxlgpu.sys` vs `amdxgpvm.sys`), not affected.

## Unknowns / Future Validation

- Whether newer AMD Adrenalin drivers (post-26.5.2) fix or change this behavior.
- Whether the fix is needed on Polaris GPUs with the AMD Pro/Enterprise driver.
- Whether the fix applies cleanly to future llama.cpp versions without
  patch conflicts.
- Whether the `GGML_VK_ALLOW_GRAPHICS_QUEUE` environment variable interacts
  with the fallback path on Polaris (it is designed for RADV performance tuning).

## Full Test Program

The test program `tests/test_vk_queues.cpp` tests all queue family combinations
and can reproduce the bug on any Polaris system:

```bash
cl test_vk_queues.cpp /I %VULKAN_SDK%\Include /link %VULKAN_SDK%\Lib\vulkan-1.lib
```

## References

- [llama.cpp Vulkan backend](https://github.com/ggerganov/llama.cpp/blob/master/ggml/src/ggml-vulkan/ggml-vulkan.cpp)
- [VK_ERROR_DEVICE_LOST — Vulkan specification](https://registry.khronos.org/vulkan/specs/1.3/html/vkspec.html#fragdev-lost)
