#define VK_USE_PLATFORM_WIN32_KHR
#include <vulkan/vulkan.h>
#include <iostream>
#include <vector>
#include <cstring>

int main() {
    // Use exactly what llama.cpp does: query max version
    VkResult res;
    PFN_vkEnumerateInstanceVersion pfnEnumVersion = 
        (PFN_vkEnumerateInstanceVersion)vkGetInstanceProcAddr(nullptr, "vkEnumerateInstanceVersion");
    uint32_t api_version = VK_API_VERSION_1_2;
    if (pfnEnumVersion) {
        pfnEnumVersion(&api_version);
    }
    std::cout << "api_version from enumerate: 0x" << std::hex << api_version << std::dec << std::endl;
    std::cout << "VK_API_VERSION_1_2 = 0x" << std::hex << VK_API_VERSION_1_2 << std::dec << std::endl;
    std::cout << "VK_API_VERSION_1_3 = 0x" << std::hex << VK_API_VERSION_1_3 << std::dec << std::endl;

    VkApplicationInfo app_info{};
    app_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = "TestExt";
    app_info.apiVersion = api_version;

    VkInstanceCreateInfo inst_info{};
    inst_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    inst_info.pApplicationInfo = &app_info;

    VkInstance instance;
    res = vkCreateInstance(&inst_info, nullptr, &instance);
    if (res != VK_SUCCESS) return 1;

    uint32_t dev_count = 0;
    vkEnumeratePhysicalDevices(instance, &dev_count, nullptr);
    std::vector<VkPhysicalDevice> phys_devices(dev_count);
    vkEnumeratePhysicalDevices(instance, &dev_count, phys_devices.data());

    for (uint32_t i = 0; i < dev_count; i++) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(phys_devices[i], &props);
        std::cout << "Device: " << props.deviceName << std::endl;
        std::cout << "  apiVersion: 0x" << std::hex << props.apiVersion << std::dec << std::endl;

        // Extension check
        uint32_t ext_count = 0;
        vkEnumerateDeviceExtensionProperties(phys_devices[i], nullptr, &ext_count, nullptr);
        std::vector<VkExtensionProperties> exts(ext_count);
        vkEnumerateDeviceExtensionProperties(phys_devices[i], nullptr, &ext_count, exts.data());

        // Queue families
        uint32_t qf_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(phys_devices[i], &qf_count, nullptr);
        std::vector<VkQueueFamilyProperties> qf_props(qf_count);
        vkGetPhysicalDeviceQueueFamilyProperties(phys_devices[i], &qf_count, qf_props.data());
        int compute_qf = -1, transfer_qf = -1;
        for (uint32_t j = 0; j < qf_count; j++) {
            std::cout << "  QF " << j << ": flags=0x" << std::hex << qf_props[j].queueFlags
                      << std::dec << " count=" << qf_props[j].queueCount << std::endl;
            if ((qf_props[j].queueFlags & VK_QUEUE_COMPUTE_BIT) && compute_qf < 0) compute_qf = j;
            if ((qf_props[j].queueFlags & VK_QUEUE_TRANSFER_BIT) && !(qf_props[j].queueFlags & VK_QUEUE_COMPUTE_BIT) && transfer_qf < 0) transfer_qf = j;
        }
        if (transfer_qf < 0) transfer_qf = compute_qf;
        std::cout << "  compute_qf=" << compute_qf << " transfer_qf=" << transfer_qf << std::endl;

        // Test 1: llama.cpp's exact extension list (5 extensions + Vk11+Vk12 in chain)
        std::vector<const char*> llama_exts = {
            "VK_KHR_maintenance4",
            "VK_KHR_pipeline_executable_properties",
            "VK_EXT_external_memory_host",
            "VK_EXT_subgroup_size_control",
            "VK_KHR_16bit_storage"
        };
        VkPhysicalDeviceFeatures base_features;
        vkGetPhysicalDeviceFeatures(phys_devices[i], &base_features);

        VkPhysicalDeviceVulkan12Features vk12{};
        vk12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;

        VkPhysicalDeviceVulkan11Features vk11{};
        vk11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
        vk11.pNext = &vk12;

        VkPhysicalDeviceFeatures2 features2{};
        features2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
        features2.features = base_features;
        features2.pNext = &vk11;

        vkGetPhysicalDeviceFeatures2(phys_devices[i], &features2);

        // Two queues like llama.cpp
        float priorities[] = {1.0f, 1.0f};
        std::vector<VkDeviceQueueCreateInfo> qcis;
        if (compute_qf != transfer_qf) {
            qcis.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, (uint32_t)compute_qf, 1, &priorities[0]});
            qcis.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, (uint32_t)transfer_qf, 1, &priorities[1]});
        } else {
            qcis.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, (uint32_t)compute_qf, 1, &priorities[0]});
        }

        VkDeviceCreateInfo dci{};
        dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = (uint32_t)qcis.size();
        dci.pQueueCreateInfos = qcis.data();
        dci.enabledExtensionCount = (uint32_t)llama_exts.size();
        dci.ppEnabledExtensionNames = llama_exts.data();
        dci.pNext = &features2;

        VkDevice device;
        res = vkCreateDevice(phys_devices[i], &dci, nullptr, &device);
        std::cout << "  Test llama-like (exts+Vk11+Vk12): " << (res == VK_SUCCESS ? "PASS" : "FAIL") << " (res=" << res << ")" << std::endl;
        if (res == VK_SUCCESS) vkDestroyDevice(device, nullptr);
    }

    vkDestroyInstance(instance, nullptr);
    std::cout << "Done." << std::endl;
    return 0;
}
