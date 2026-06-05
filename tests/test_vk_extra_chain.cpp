#define VK_USE_PLATFORM_WIN32_KHR
#include <vulkan/vulkan.h>
#include <iostream>
#include <vector>
#include <cstring>

int main() {
    uint32_t api_version = VK_API_VERSION_1_2;
    PFN_vkEnumerateInstanceVersion pfnEnumVersion = 
        (PFN_vkEnumerateInstanceVersion)vkGetInstanceProcAddr(nullptr, "vkEnumerateInstanceVersion");
    if (pfnEnumVersion) pfnEnumVersion(&api_version);

    VkApplicationInfo app_info{};
    app_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = "Test";
    app_info.apiVersion = api_version;

    VkInstanceCreateInfo inst_info{};
    inst_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    inst_info.pApplicationInfo = &app_info;

    VkInstance instance;
    VkResult res = vkCreateInstance(&inst_info, nullptr, &instance);
    if (res != VK_SUCCESS) return 1;

    uint32_t dev_count = 0;
    vkEnumeratePhysicalDevices(instance, &dev_count, nullptr);
    std::vector<VkPhysicalDevice> phys_devices(dev_count);
    vkEnumeratePhysicalDevices(instance, &dev_count, phys_devices.data());

    for (uint32_t i = 0; i < dev_count; i++) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(phys_devices[i], &props);
        std::cout << "Device: " << props.deviceName << std::endl;

        // Queue families
        uint32_t qf_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(phys_devices[i], &qf_count, nullptr);
        std::vector<VkQueueFamilyProperties> qf_props(qf_count);
        vkGetPhysicalDeviceQueueFamilyProperties(phys_devices[i], &qf_count, qf_props.data());
        int compute_qf = -1, transfer_qf = -1;
        for (uint32_t j = 0; j < qf_count; j++) {
            if ((qf_props[j].queueFlags & VK_QUEUE_COMPUTE_BIT) && compute_qf < 0) compute_qf = j;
            if ((qf_props[j].queueFlags & VK_QUEUE_TRANSFER_BIT) && !(qf_props[j].queueFlags & VK_QUEUE_COMPUTE_BIT) && transfer_qf < 0) transfer_qf = j;
        }
        if (transfer_qf < 0) transfer_qf = compute_qf;

        VkPhysicalDeviceFeatures base_features;
        vkGetPhysicalDeviceFeatures(phys_devices[i], &base_features);

        std::vector<const char*> exts = {
            "VK_KHR_maintenance4", "VK_KHR_pipeline_executable_properties",
            "VK_EXT_external_memory_host", "VK_EXT_subgroup_size_control", "VK_KHR_16bit_storage"
        };

        float priorities[] = {1.0f, 1.0f};
        std::vector<VkDeviceQueueCreateInfo> qcis;
        if (compute_qf != transfer_qf) {
            qcis.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, (uint32_t)compute_qf, 1, &priorities[0]});
            qcis.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, (uint32_t)transfer_qf, 1, &priorities[1]});
        } else {
            qcis.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, (uint32_t)compute_qf, 1, &priorities[0]});
        }

        // Test with EXACT llama.cpp chain: Vk11+Vk12+subgroup+maint4+pep
        VkPhysicalDevicePipelineExecutablePropertiesFeaturesKHR pep{};
        pep.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PIPELINE_EXECUTABLE_PROPERTIES_FEATURES_KHR;
        pep.pipelineExecutableInfo = VK_TRUE;

        VkPhysicalDeviceMaintenance4Features maint4{};
        maint4.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_4_FEATURES;
        maint4.pNext = &pep;
        maint4.maintenance4 = VK_TRUE;

        VkPhysicalDeviceSubgroupSizeControlFeaturesEXT subgroup{};
        subgroup.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_SIZE_CONTROL_FEATURES_EXT;
        subgroup.pNext = &maint4;
        subgroup.subgroupSizeControl = VK_TRUE;
        subgroup.computeFullSubgroups = VK_FALSE;

        VkPhysicalDeviceVulkan12Features vk12{};
        vk12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
        vk12.pNext = &subgroup;

        VkPhysicalDeviceVulkan11Features vk11{};
        vk11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
        vk11.pNext = &vk12;

        VkPhysicalDeviceFeatures2 features2{};
        features2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
        features2.features = base_features;
        features2.pNext = &vk11;

        // Query features first (like llama.cpp does)
        vkGetPhysicalDeviceFeatures2(phys_devices[i], &features2);

        VkDeviceCreateInfo dci{};
        dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = (uint32_t)qcis.size();
        dci.pQueueCreateInfos = qcis.data();
        dci.enabledExtensionCount = (uint32_t)exts.size();
        dci.ppEnabledExtensionNames = exts.data();
        dci.pNext = &features2;

        VkDevice device;
        res = vkCreateDevice(phys_devices[i], &dci, nullptr, &device);
        std::cout << "  llama-cpp EXACT chain (Vk11+Vk12+subgroup+maint4+pep): " 
                  << (res == VK_SUCCESS ? "PASS" : "FAIL") << " (res=" << res << ")" << std::endl;
        if (res == VK_SUCCESS) vkDestroyDevice(device, nullptr);
        
        // Test: same but without pep
        maint4.pNext = nullptr;
        VkDeviceCreateInfo dci2 = dci;
        res = vkCreateDevice(phys_devices[i], &dci2, nullptr, &device);
        std::cout << "  without pep: " << (res == VK_SUCCESS ? "PASS" : "FAIL") << " (res=" << res << ")" << std::endl;
        if (res == VK_SUCCESS) vkDestroyDevice(device, nullptr);
        maint4.pNext = &pep;

        // Test: same but without maint4
        subgroup.pNext = nullptr;
        VkDeviceCreateInfo dci3 = dci;
        res = vkCreateDevice(phys_devices[i], &dci3, nullptr, &device);
        std::cout << "  without maint4: " << (res == VK_SUCCESS ? "PASS" : "FAIL") << " (res=" << res << ")" << std::endl;
        if (res == VK_SUCCESS) vkDestroyDevice(device, nullptr);
        subgroup.pNext = &maint4;

        // Test: same but without subgroup
        vk12.pNext = nullptr;
        VkDeviceCreateInfo dci4 = dci;
        res = vkCreateDevice(phys_devices[i], &dci4, nullptr, &device);
        std::cout << "  without subgroup: " << (res == VK_SUCCESS ? "PASS" : "FAIL") << " (res=" << res << ")" << std::endl;
        if (res == VK_SUCCESS) vkDestroyDevice(device, nullptr);
        vk12.pNext = &subgroup;
    }

    vkDestroyInstance(instance, nullptr);
    std::cout << "Done." << std::endl;
    return 0;
}
