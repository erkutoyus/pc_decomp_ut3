"""Prepare the pinned DXVK Native source and the shared UT3 renderer patches."""
import hashlib
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REVISION = "0cf05780abd7250c2cd713b7749cf32180157cf5"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(path, value):
    data = value.encode() if isinstance(value, str) else value
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)

def run(args, **kwargs):
    print(subprocess.list2cmdline([str(x) for x in args]), flush=True)
    subprocess.run([str(x) for x in args], check=True, **kwargs)

def prepare_source(pins, SOURCE, WORK, *, platform="android"):
    """Validate the source tree and apply the shared UT3 DXVK overlays."""
    overlay = {}

    def replace_all(path, before, after, count):
        value = overlay.get(path)
        if value is None:
            value = (SOURCE / path.relative_to(WORK)).read_text(encoding="utf-8")
        if value.count(before) != count:
            raise ValueError(f"DXVK overlay context mismatch: {path}: {before[:80]}")
        overlay[path] = value.replace(before, after)

    def replace(path, before, after):
        replace_all(path, before, after, 1)

    pristine = {}
    for name, expected in pins["source_files"].items():
        path = SOURCE / name
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            if platform != "apple" or hashlib.sha256(data.replace(b"\n", b"\r\n")).hexdigest() != expected:
                raise ValueError("DXVK source hash mismatch: " + name)
        pristine[WORK / name] = data
    if platform == "android":
        replace(WORK / "meson.build", "  if (not lib_sdl2.found() and not lib_glfw.found())",
                "  if platform == 'android'\n    compiler_args += ['-DDXVK_WSI_ANDROID']\n    link_args += ['-landroid', '-ldl', '-Wl,-z,max-page-size=16384']\n  endif\n  if platform != 'android' and (not lib_sdl2.found() and not lib_glfw.found())")
        replace(WORK / "src/wsi/meson.build", "  'wsi_platform.cpp',", "  'wsi_platform.cpp',\n  'wsi_android.cpp',")
        replace(WORK / "src/wsi/meson.build", "if platform != 'windows'", "if platform != 'windows' and platform != 'android'")
    replace(WORK / "src/wsi/wsi_platform.h", "  void init();", "#if defined(DXVK_WSI_ANDROID)\n  extern WsiBootstrap AndroidWSI;\n#endif\n\n  void init();")
    replace(WORK / "src/wsi/wsi_platform.cpp", "  static const WsiBootstrap *wsiBootstrap[] = {", "  static const WsiBootstrap *wsiBootstrap[] = {\n#if defined(DXVK_WSI_ANDROID)\n    &AndroidWSI,\n#endif")
    replace(WORK / "src/d3d9/d3d9.sym", "    Direct3DCreate9;", "    Direct3DCreate9;\n    ut3_dxvk_set_callbacks_v2;\n    ut3_dxvk_set_vulkan_loader;")
    replace(WORK / "src/vulkan/vulkan_loader.cpp", "namespace dxvk::vk {",
            "#if defined(DXVK_WSI_ANDROID)\nextern \"C\" PFN_vkGetInstanceProcAddr ut3_dxvk_native_vulkan_loader();\n#endif\n\nnamespace dxvk::vk {")
    replace(WORK / "src/vulkan/vulkan_loader.cpp", "  LibraryLoader::LibraryLoader() {\n",
            "  LibraryLoader::LibraryLoader() {\n#if defined(DXVK_WSI_ANDROID)\n"
            "    if (auto loader = ut3_dxvk_native_vulkan_loader()) {\n"
            "      m_getInstanceProcAddr = loader;\n      return;\n    }\n#endif\n")
    # textureCompressionBC guarantees the entire BC family, including BC6/7.
    # Android GPUs may support D3D9's BC1-5 individually without that aggregate
    # feature. Keep native CheckDeviceFormat's Vulkan format checks unchanged.
    replace(WORK / "src/d3d9/d3d9_device.cpp",
            "    enabled.core.features.textureCompressionBC = VK_TRUE;",
            "#if defined(DXVK_WSI_ANDROID)\n"
            "    enabled.core.features.textureCompressionBC = supported.core.features.textureCompressionBC;\n"
            "#else\n    enabled.core.features.textureCompressionBC = VK_TRUE;\n#endif")
    # Occlusion query pools: PowerVR's proprietary driver loses sample counts in a 16384-entry pool
    # and starts a new render (store and reload of every attachment) whenever a query uses another
    # pool than the query before it. 4096-entry pools there, and handles come from one pool until it
    # is used up instead of upstream's LIFO list over all pools: engine/dxvk/query_pools.inc.
    write(WORK / "src/dxvk/dxvk_query_pools.inc", (ROOT / "engine/dxvk/query_pools.inc").read_bytes())
    replace(WORK / "src/dxvk/dxvk_gpu_query.h",
            "    dxvk::mutex                     m_mutex;\n    std::vector<DxvkGpuQueryHandle> m_handles;\n    std::vector<VkQueryPool>        m_pools;\n",
            "    dxvk::mutex                     m_mutex;\n"
            "    // Free handles of each pool (parallel to m_pools), see dxvk_query_pools.inc\n"
            "    std::vector<std::vector<DxvkGpuQueryHandle>> m_handles;\n"
            "    std::vector<VkQueryPool>        m_pools;\n"
            "    size_t                          m_currentPool = 0;\n")
    replace(WORK / "src/dxvk/dxvk_gpu_query.cpp",
            "  DxvkGpuQueryHandle DxvkGpuQueryAllocator::allocQuery() {\n    std::lock_guard<dxvk::mutex> lock(m_mutex);\n\n"
            "    if (m_handles.size() == 0)\n      this->createQueryPool();\n\n    if (m_handles.size() == 0)\n      return DxvkGpuQueryHandle();\n    \n"
            "    DxvkGpuQueryHandle result = m_handles.back();\n    m_handles.pop_back();\n    return result;\n  }\n\n\n"
            "  void DxvkGpuQueryAllocator::freeQuery(DxvkGpuQueryHandle handle) {\n    std::lock_guard<dxvk::mutex> lock(m_mutex);\n"
            "    m_handles.push_back(handle);\n  }\n",
            "#include \"dxvk_query_pools.inc\"\n")
    replace(WORK / "src/dxvk/dxvk_gpu_query.cpp",
            "    m_pools.push_back(queryPool);\n\n    for (uint32_t i = 0; i < m_queryPoolSize; i++)\n      m_handles.push_back({ this, queryPool, i });\n",
            "    m_pools.push_back(queryPool);\n    m_handles.emplace_back();\n    m_handles.back().reserve(m_queryPoolSize);\n\n"
            "    for (uint32_t i = 0; i < m_queryPoolSize; i++)\n      m_handles.back().push_back({ this, queryPool, i });\n")
    replace(WORK / "src/dxvk/dxvk_gpu_query.cpp",
            "  : m_occlusion(device, VK_QUERY_TYPE_OCCLUSION,                     16384),",
            "  : m_occlusion(device, VK_QUERY_TYPE_OCCLUSION,                     occlusionQueryPoolSize(device)),")
    # Qualcomm's proprietary Adreno driver has no *_SCALED vertex buffer formats (D3D9 UBYTE4,
    # SHORT2/4, UDEC3); DXVK then drops those draws (UE3 terrain). Fetch the mandatory UINT/SINT
    # formats instead and convert in the vertex shader: engine/dxvk/scaled_vertex_formats.inc.
    write(WORK / "src/dxvk/dxvk_scaled_vertex.h", (ROOT / "engine/dxvk/scaled_vertex_formats.inc").read_bytes())
    write(WORK / "src/dxvk/dxvk_scaled_vertex_spirv.inc", (ROOT / "engine/dxvk/scaled_vertex_spirv.inc").read_bytes())
    replace(WORK / "src/dxvk/dxvk_shader.h", "    uint32_t  undefinedInputs = 0;\n",
            "    uint32_t  undefinedInputs = 0;\n    uint32_t  vsUintInputs    = 0;\n    uint32_t  vsSintInputs    = 0;\n")
    replace(WORK / "src/dxvk/dxvk_shader.h", "    static void eliminateInput(\n",
            "    static void convertIntegerInput(\n            SpirvCodeBuffer&          code,\n"
            "            uint32_t                  location,\n            bool                      isSigned);\n\n"
            "    static void eliminateInput(\n")
    replace(WORK / "src/dxvk/dxvk_shader.cpp", "           && undefinedInputs == other.undefinedInputs;",
            "           && undefinedInputs == other.undefinedInputs\n"
            "           && vsUintInputs    == other.vsUintInputs\n"
            "           && vsSintInputs    == other.vsSintInputs;")
    replace(WORK / "src/dxvk/dxvk_shader.cpp", "    hash.add(undefinedInputs);\n",
            "    hash.add(undefinedInputs);\n    hash.add(vsUintInputs);\n    hash.add(vsSintInputs);\n")
    replace(WORK / "src/dxvk/dxvk_shader.cpp", "      eliminateInput(spirvCode, u);\n",
            "      eliminateInput(spirvCode, u);\n\n"
            "    // Integer fetch of SCALED vertex formats, see dxvk_scaled_vertex.h\n"
            "    for (uint32_t u : bit::BitMask(state.vsUintInputs))\n"
            "      convertIntegerInput(spirvCode, u, false);\n"
            "    for (uint32_t u : bit::BitMask(state.vsSintInputs))\n"
            "      convertIntegerInput(spirvCode, u, true);\n"
            "    if (bit::popcnt(state.vsUintInputs) > 1 || bit::popcnt(state.vsSintInputs) > 1) {\n"
            "      static std::atomic<bool> reported = { false };\n"
            "      if (!reported.exchange(true))\n"
            "        Logger::info(str::format(\"DXVK: SCALED vertex fallback: a shader converts \",\n"
            "          bit::popcnt(state.vsUintInputs), \" unsigned and \", bit::popcnt(state.vsSintInputs), \" signed inputs\"));\n"
            "    }\n")
    replace(WORK / "src/dxvk/dxvk_shader.cpp", "  void DxvkShader::eliminateInput(SpirvCodeBuffer& code, uint32_t location) {\n",
            "#include \"dxvk_scaled_vertex_spirv.inc\"\n\n  void DxvkShader::eliminateInput(SpirvCodeBuffer& code, uint32_t location) {\n")
    replace(WORK / "src/dxvk/dxvk_graphics.h",
            "    DxvkGraphicsPipelineShaderState(\n      const DxvkGraphicsPipelineShaders&    shaders,\n",
            "    DxvkGraphicsPipelineShaderState(\n      const DxvkDevice*                     device,\n      const DxvkGraphicsPipelineShaders&    shaders,\n")
    replace(WORK / "src/dxvk/dxvk_graphics.h",
            "    DxvkShaderModuleCreateInfo getCreateInfo(\n      const DxvkGraphicsPipelineShaders&    shaders,\n",
            "    DxvkShaderModuleCreateInfo getCreateInfo(\n      const DxvkDevice*                     device,\n      const DxvkGraphicsPipelineShaders&    shaders,\n")
    replace(WORK / "src/dxvk/dxvk_graphics.h", "    : shState(shaders, state),", "    : shState(device, shaders, state),")
    replace(WORK / "src/dxvk/dxvk_graphics.cpp", "#include \"dxvk_pipemanager.h\"\n",
            "#include \"dxvk_pipemanager.h\"\n#include \"dxvk_scaled_vertex.h\"\n")
    replace(WORK / "src/dxvk/dxvk_graphics.cpp", "        attr.format = state.ilAttributes[i].format();\n",
            "        uint32_t conversion = 0;\n"
            "        attr.format = scaledVertexFetchFormat(device, state.ilAttributes[i].format(), &conversion);\n")
    replace(WORK / "src/dxvk/dxvk_graphics.cpp",
            "  DxvkGraphicsPipelineShaderState::DxvkGraphicsPipelineShaderState(\n    const DxvkGraphicsPipelineShaders&    shaders,\n    const DxvkGraphicsPipelineStateInfo&  state)\n"
            "  : vsInfo  (getCreateInfo(shaders, shaders.vs, state)),\n    tcsInfo (getCreateInfo(shaders, shaders.tcs, state)),\n"
            "    tesInfo (getCreateInfo(shaders, shaders.tes, state)),\n    gsInfo  (getCreateInfo(shaders, shaders.gs, state)),\n"
            "    fsInfo  (getCreateInfo(shaders, shaders.fs, state)) {",
            "  DxvkGraphicsPipelineShaderState::DxvkGraphicsPipelineShaderState(\n    const DxvkDevice*                     device,\n"
            "    const DxvkGraphicsPipelineShaders&    shaders,\n    const DxvkGraphicsPipelineStateInfo&  state)\n"
            "  : vsInfo  (getCreateInfo(device, shaders, shaders.vs, state)),\n    tcsInfo (getCreateInfo(device, shaders, shaders.tcs, state)),\n"
            "    tesInfo (getCreateInfo(device, shaders, shaders.tes, state)),\n    gsInfo  (getCreateInfo(device, shaders, shaders.gs, state)),\n"
            "    fsInfo  (getCreateInfo(device, shaders, shaders.fs, state)) {")
    replace(WORK / "src/dxvk/dxvk_graphics.cpp",
            "  DxvkShaderModuleCreateInfo DxvkGraphicsPipelineShaderState::getCreateInfo(\n    const DxvkGraphicsPipelineShaders&    shaders,\n",
            "  DxvkShaderModuleCreateInfo DxvkGraphicsPipelineShaderState::getCreateInfo(\n    const DxvkDevice*                     device,\n    const DxvkGraphicsPipelineShaders&    shaders,\n")
    replace(WORK / "src/dxvk/dxvk_graphics.cpp",
            "      for (uint32_t i = 0; i < state.il.attributeCount(); i++)\n        providedInputs |= 1u << state.ilAttributes[i].location();\n",
            "      for (uint32_t i = 0; i < state.il.attributeCount(); i++) {\n"
            "        uint32_t location = state.ilAttributes[i].location();\n"
            "        uint32_t conversion = 0;\n"
            "        providedInputs |= 1u << location;\n"
            "        if (consumedInputs & (1u << location)) {\n"
            "          scaledVertexFetchFormat(device, state.ilAttributes[i].format(), &conversion);\n"
            "          if (conversion == 1) info.vsUintInputs |= 1u << location;\n"
            "          if (conversion == 2) info.vsSintInputs |= 1u << location;\n"
            "        }\n"
            "      }\n")
    # Base (GPL fast-link) pipelines use the unpatched vertex shader library.
    replace(WORK / "src/dxvk/dxvk_graphics.cpp",
            "    if (m_shaders.tcs != nullptr) {\n      // If tessellation shaders are present, the input patch\n",
            "    for (uint32_t i = 0; i < state.il.attributeCount(); i++) {\n"
            "      uint32_t conversion = 0;\n"
            "      if (m_shaders.vs->info().inputMask & (1u << state.ilAttributes[i].location()))\n"
            "        scaledVertexFetchFormat(m_device, state.ilAttributes[i].format(), &conversion);\n"
            "      if (conversion)\n        return false;\n    }\n\n"
            "    if (m_shaders.tcs != nullptr) {\n      // If tessellation shaders are present, the input patch\n")
    replace(WORK / "src/dxvk/dxvk_graphics.cpp",
            "      DxvkFormatFeatures formatInfo = m_device->getFormatFeatures(attribute.format());\n",
            "      uint32_t conversion = 0;\n"
            "      DxvkFormatFeatures formatInfo = m_device->getFormatFeatures(\n"
            "        scaledVertexFetchFormat(m_device, attribute.format(), &conversion));\n")
    # Persistent VkPipelineCache shared by all pipeline creation: engine/dxvk/pipeline_cache.inc.
    write(WORK / "src/dxvk/dxvk_pipecache_file.h", (ROOT / "engine/dxvk/pipeline_cache.inc").read_bytes())
    replace(WORK / "src/dxvk/dxvk_device.h", "#include \"dxvk_options.h\"\n",
            "#include \"dxvk_options.h\"\n#include \"dxvk_pipecache_file.h\"\n")
    replace(WORK / "src/dxvk/dxvk_device.h", "    DxvkObjects                 m_objects;\n",
            "    DxvkPipelineCacheFile       m_pipelineCache;\n    DxvkObjects                 m_objects;\n")
    replace(WORK / "src/dxvk/dxvk_device.h", "    const DxvkDeviceFeatures& features() const {\n",
            "    /**\n     * \\brief Pipeline cache for one pipeline creation call\n     */\n"
            "    VkPipelineCache usePipelineCache() const {\n      return m_pipelineCache.use();\n    }\n\n"
            "    const DxvkDeviceFeatures& features() const {\n")
    replace(WORK / "src/dxvk/dxvk_device.cpp", "    m_perfHints         (getPerfHints()),\n",
            "    m_perfHints         (getPerfHints()),\n    m_pipelineCache     (vkd, adapter->devicePropertiesExt()),\n")
    replace_all(WORK / "src/dxvk/dxvk_graphics.cpp", "vk->vkCreateGraphicsPipelines(vk->device(),\n      VK_NULL_HANDLE,",
                "vk->vkCreateGraphicsPipelines(vk->device(),\n      m_device->usePipelineCache(),", 2)
    replace_all(WORK / "src/dxvk/dxvk_graphics.cpp", "vk->vkCreateGraphicsPipelines(vk->device(), VK_NULL_HANDLE,",
                "vk->vkCreateGraphicsPipelines(vk->device(), m_device->usePipelineCache(),", 2)
    replace_all(WORK / "src/dxvk/dxvk_shader.cpp", "vk->vkCreateGraphicsPipelines(vk->device(), VK_NULL_HANDLE,",
                "vk->vkCreateGraphicsPipelines(vk->device(), m_device->usePipelineCache(),", 2)
    replace_all(WORK / "src/dxvk/dxvk_shader.cpp", "vk->vkCreateComputePipelines(vk->device(), VK_NULL_HANDLE,",
                "vk->vkCreateComputePipelines(vk->device(), m_device->usePipelineCache(),", 1)
    replace_all(WORK / "src/dxvk/dxvk_compute.cpp", "vk->vkCreateComputePipelines(vk->device(),\n          VK_NULL_HANDLE,",
                "vk->vkCreateComputePipelines(vk->device(),\n          m_device->usePipelineCache(),", 1)
    if platform == "android":
        replace(WORK / "src/util/thread.h", "namespace dxvk {", "#if defined(__ANDROID__)\nextern \"C\" void ut3_dxvk_native_worker_enter();\n#endif\n\nnamespace dxvk {")
        replace(WORK / "src/util/thread.h", "  class thread : public std::thread {\n  public:\n    using std::thread::thread;", """  class thread : public std::thread {
  public:
#if defined(__ANDROID__)
    thread() = default;
    thread(thread&&) noexcept = default;
    thread& operator = (thread&&) noexcept = default;
    template<typename Function>
    explicit thread(Function&& function)
    : std::thread([proc = std::forward<Function>(function)]() mutable {
        ut3_dxvk_native_worker_enter();
        proc();
      }) { }
#else
    using std::thread::thread;
#endif""")
    replace(WORK / "src/dxvk/dxvk_presenter.cpp", "namespace dxvk {", "#if defined(__ANDROID__)\nextern \"C\" void ut3_dxvk_native_present_notify(const void*, uint64_t, int32_t);\n#endif\nnamespace dxvk {")
    replace(WORK / "src/dxvk/dxvk_presenter.cpp", "  Presenter::~Presenter() {\n", "  Presenter::~Presenter() {\n#if defined(__ANDROID__)\n    ut3_dxvk_native_present_notify(this, 0, VK_NOT_READY);\n#endif\n")
    replace(WORK / "src/dxvk/dxvk_presenter.cpp", "    // Try to acquire next image already", "#if defined(__ANDROID__)\n    if (frameId) ut3_dxvk_native_present_notify(this, frameId, status);\n#endif\n\n    // Try to acquire next image already")
    replace(WORK / "src/d3d9/d3d9_swapchain.cpp", "    if (status != VK_SUCCESS)\n      RecreateSwapChain();\n  }\n\n  void D3D9SwapChainEx::RecreateSwapChain()", "#if defined(DXVK_WSI_ANDROID)\n    if (status != VK_SUCCESS && status != VK_SUBOPTIMAL_KHR)\n#else\n    if (status != VK_SUCCESS)\n#endif\n      RecreateSwapChain();\n  }\n\n  void D3D9SwapChainEx::RecreateSwapChain()")
    # Compare only final composed bytes; restoring a pristine shared header
    # before patching would unnecessarily invalidate every native DXVK TU.
    for path, data in pristine.items():
        write(path, overlay.get(path, data))


