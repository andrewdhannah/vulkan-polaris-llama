#define VK_USE_PLATFORM_WIN32_KHR
#include <vulkan/vulkan.h>
#include <iostream>
#include <vector>
#include <cstring>

int main() {
    uint32_t api_version = VK_API_VERSION_1_2;
    PFN_vkEnumerateInstanceVersion pfn = (PFN_vkEnumerateInstanceVersion)vkGetInstanceProcAddr(nullptr, "vkEnumerateInstanceVersion");
    if (pfn) pfn(&api_version);

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

        uint32_t qf_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(phys_devices[i], &qf_count, nullptr);
        std::vector<VkQueueFamilyProperties> qf_props(qf_count);
        vkGetPhysicalDeviceQueueFamilyProperties(phys_devices[i], &qf_count, qf_props.data());
        
        // Use EXACTLY llama.cpp's queue selection logic
        int compute_qf = -1;
        for (uint32_t j = 0; j < qf_count; j++) {
            if ((qf_props[j].queueFlags & VK_QUEUE_COMPUTE_BIT) && !(qf_props[j].queueFlags & VK_QUEUE_GRAPHICS_BIT) && compute_qf < 0) {
                compute_qf = j;
            }
        }
        if (compute_qf < 0) {
            for (uint32_t j = 0; j < qf_count; j++) {
                if ((qf_props[j].queueFlags & VK_QUEUE_COMPUTE_BIT) && compute_qf < 0) compute_qf = j;
            }
        }

        int transfer_qf = -1;
        for (uint32_t j = 0; j < qf_count; j++) {
            if (j != (uint32_t)compute_qf &&
                (qf_props[j].queueFlags & VK_QUEUE_TRANSFER_BIT) &&
                !(qf_props[j].queueFlags & (VK_QUEUE_COMPUTE_BIT | VK_QUEUE_GRAPHICS_BIT)) &&
                transfer_qf < 0) {
                transfer_qf = j;
            }
        }
        if (transfer_qf < 0) {
            for (uint32_t j = 0; j < qf_count; j++) {
                if (j != (uint32_t)compute_qf && (qf_props[j].queueFlags & VK_QUEUE_TRANSFER_BIT) && transfer_qf < 0) transfer_qf = j;
            }
        }
        if (transfer_qf < 0) transfer_qf = compute_qf;

        std::cout << "  compute_qf=" << compute_qf << " transfer_qf=" << transfer_qf << std::endl;

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

        // TEST 1: exact llama.cpp pNext chain
        VkPhysicalDevicePipelineExecutablePropertiesFeaturesKHR pep{};
        pep.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PIPELINE_EXECUTABLE_PROPERTIES_FEATURES_KHR;
        VkPhysicalDeviceMaintenance4Features maint4{};
        maint4.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_4_FEATURES;
        maint4.pNext = &pep;
        VkPhysicalDeviceSubgroupSizeControlFeaturesEXT subgroup{};
        subgroup.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_SIZE_CONTROL_FEATURES_EXT;
        subgroup.pNext = &maint4;
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
        std::cout << "  llama-exact-qfs (qf=" << compute_qf << "+" << transfer_qf << "): " 
                  << (res == VK_SUCCESS ? "PASS" : "FAIL") << " (res=" << res << ")" << std::endl;
        if (res == VK_SUCCESS) vkDestroyDevice(device, nullptr);

        // TEST 2: same but with simpler selection (qf 0 for compute)
        int alt_compute = 0;
        int alt_transfer = (qf_count > 2 && (qf_props[2].queueFlags & VK_QUEUE_TRANSFER_BIT)) ? 2 : (qf_count > 1 ? 1 : 0);
        std::cout << "  alt qfs: compute=" << alt_compute << " transfer=" << alt_transfer << std::endl;
        
        std::vector<VkDeviceQueueCreateInfo> alt_qcis;
        if (alt_compute != alt_transfer && alt_transfer < (int)qf_count) {
            alt_qcis.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, (uint32_t)alt_compute, 1, &priorities[0]});
            alt_qcis.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, (uint32_t)alt_transfer, 1, &priorities[1]});
        } else {
            alt_qcis.push_back({VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, nullptr, 0, (uint32_t)alt_compute, 1, &priorities[0]});
        }
        dci.queueCreateInfoCount = (uint32_t)alt_qcis.size();
        dci.pQueueCreateInfos = alt_qcis.data();
        res = vkCreateDevice(phys_devices[i], &dci, nullptr, &device);
        std::cout << "  llama-alt-qfs (qf=" << alt_compute << "+" << alt_transfer << "): " 
                  << (res == VK_SUCCESS ? "PASS" : "FAIL") << " (res=" << res << ")" << std::endl;
        if (res == VK_SUCCESS) vkDestroyDevice(device, nullptr);
    }

    vkDestroyInstance(instance, nullptr);
    std::cout << "Done." << std::endl;
    return 0;
}
