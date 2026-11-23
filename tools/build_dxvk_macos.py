"""Build the pinned native DXVK D3D9 renderer for the Apple Metal WSI."""
import argparse
import json
import os
from pathlib import Path

from dxvk_source import ROOT, REVISION, prepare_source, run, sha, write


def edit(root, name, before, after, count=1):
    path = root / name
    contents = path.read_text(encoding="utf-8")
    if contents.count(before) != count:
        raise ValueError(f"Apple overlay context mismatch: {name}: {before[:90]}")
    write(path, contents.replace(before, after))


def split_shadow_descriptors(source, device):
    # A DXSO program has ordinary and comparison sample instructions, selected
    # at draw time. A color view in the comparison binding is invalid even
    # when the corresponding branch is unreachable for the current texture.
    edit(source, "src/dxso/dxso_util.h", "  uint32_t RegisterLinkerSlot",
         "  constexpr uint32_t getShadowSamplerSlot(uint32_t colorSlot) {\n"
         "    return colorSlot + getSpecConstantBufferSlot() + 1;\n"
         "  }\n\n  uint32_t RegisterLinkerSlot")
    compiler = "src/dxso/dxso_compiler.cpp"
    edit(source, compiler, "      m_module.decorateBinding      (sampler.varId, bindingId);",
         "      m_module.decorateBinding      (sampler.varId, depth ? getShadowSamplerSlot(bindingId) : bindingId);")
    edit(source, compiler, "    m_bindings.push_back(bindingInfo);\n  }\n\n\n  uint32_t DxsoCompiler::emitArrayIndex",
         "    m_bindings.push_back(bindingInfo);\n"
         "    if (implicit || SamplerTypeFromTextureType(type) != SamplerTypeTexture3D) {\n"
         "      bindingInfo.resourceBinding = getShadowSamplerSlot(binding);\n"
         "      m_bindings.push_back(bindingInfo);\n"
         "    }\n  }\n\n\n  uint32_t DxsoCompiler::emitArrayIndex")
    edit(source, device, "        ctx->bindResourceSampler(stage, cSlot,\n          Rc<DxvkSampler>(pair->second));",
         "        ctx->bindResourceSampler(stage, cSlot, Rc<DxvkSampler>(pair->second));\n"
         "        ctx->bindResourceSampler(stage, getShadowSamplerSlot(cSlot), Rc<DxvkSampler>(pair->second));")
    edit(source, device, "        ctx->bindResourceSampler(stage, cSlot, std::move(sampler));",
         "        ctx->bindResourceSampler(stage, cSlot, Rc<DxvkSampler>(sampler));\n"
         "        ctx->bindResourceSampler(stage, getShadowSamplerSlot(cSlot), std::move(sampler));")
    edit(source, device, "      cSlot = slot,\n      cImageView = commonTex->GetSampleView(srgb)",
         "      cSlot = slot,\n      cDepth = (m_depthTextures & (1u << StateSampler)) != 0,\n"
         "      cImageView = commonTex->GetSampleView(srgb)")
    edit(source, device, "      ctx->bindResourceImageView(stage, cSlot, std::move(cImageView));",
         "      ctx->bindResourceImageView(stage, getShadowSamplerSlot(cSlot), cDepth ? cImageView : nullptr);\n"
         "      ctx->bindResourceImageView(stage, cSlot, std::move(cImageView));")
    edit(source, device, "        ctx->bindResourceImageView(stage, slot, nullptr);",
         "        ctx->bindResourceImageView(stage, slot, nullptr);\n"
         "        ctx->bindResourceImageView(stage, getShadowSamplerSlot(slot), nullptr);", count=2)


def apply_apple(source):
    for name in ("metal_window.h", "metal_wsi.cpp"):
        write(source / "src/wsi" / name, (ROOT / "platform/apple" / name).read_bytes())
    edit(source, "meson.build",
         "  if (not lib_sdl2.found() and not lib_glfw.found())",
         "  if platform == 'darwin'\n    compiler_args += ['-DDXVK_WSI_APPLE']\n  endif\n"
         "  if platform != 'darwin' and (not lib_sdl2.found() and not lib_glfw.found())")
    # Select a single native WSI without SDL/GLFW ownership of the AppKit window.
    for package, macro in (("sdl2", "SDL2"), ("glfw", "GLFW")):
        edit(source, "meson.build", f"  if lib_{package}.found()\n    compiler_args += ['-DDXVK_WSI_{macro}']",
             f"  if platform != 'darwin' and lib_{package}.found()\n    compiler_args += ['-DDXVK_WSI_{macro}']")
    edit(source, "src/wsi/meson.build", "  'wsi_platform.cpp',", "  'wsi_platform.cpp',\n  'metal_wsi.cpp',")
    edit(source, "src/wsi/meson.build", "if platform != 'windows'",
         "if platform != 'windows' and platform != 'darwin'")
    for name in ("src/wsi/wsi_platform.cpp", "src/wsi/wsi_platform.h", "src/vulkan/vulkan_loader.cpp",
                 "src/d3d9/d3d9_device.cpp", "src/d3d9/d3d9_swapchain.cpp"):
        path = source / name
        write(path, path.read_text().replace("DXVK_WSI_ANDROID", "DXVK_WSI_APPLE").replace("AndroidWSI", "AppleWSI"))
    edit(source, "src/d3d9/meson.build", "if platform != 'windows'\n  d3d9_ld_args",
         "if platform == 'darwin'\n"
         "  foreach symbol : ['Direct3DCreate9', 'ut3_dxvk_set_callbacks_v2', 'ut3_dxvk_set_vulkan_loader']\n"
         "    d3d9_ld_args += ['-Wl,-exported_symbol,_' + symbol]\n"
         "  endforeach\n"
         "elif platform != 'windows'\n  d3d9_ld_args")
    edit(source, "src/vulkan/vulkan_loader.cpp", "#include <tuple>", "#include <tuple>\n#include <cstdlib>")
    edit(source, "src/vulkan/vulkan_loader.cpp", "    static const std::array<const char*, 2> dllNames = {{",
         "    const std::array<const char*, 2> dllNames = {{")
    edit(source, "src/vulkan/vulkan_loader.cpp", '#else\n      "libvulkan.so",',
         '#elif defined(__APPLE__)\n      std::getenv("UT3_VULKAN_LOADER"),\n      "libvulkan.1.dylib",\n#else\n      "libvulkan.so",')
    edit(source, "src/vulkan/vulkan_loader.cpp", "    for (auto dllName : dllNames) {",
         "    for (auto dllName : dllNames) {\n      if (!dllName || !*dllName) continue;")
    edit(source, "src/vulkan/vulkan_loader.cpp", "    return m_getInstanceProcAddr(instance, name);",
         "    return m_getInstanceProcAddr ? m_getInstanceProcAddr(instance, name) : nullptr;")
    edit(source, "src/dxvk/dxvk_instance.cpp", "      : new vk::LibraryFn();",
         '      : new vk::LibraryFn();\n    if (!m_vkl->valid())\n      throw DxvkError("Vulkan loader is unavailable");')
    edit(source, "src/dxvk/dxvk_instance.cpp", "      // Generate list of extensions to enable",
         '#ifdef DXVK_WSI_APPLE\n'
         '      if (extensionsAvailable.supports(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME))\n'
         '        extensionSet.add(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);\n'
         '#endif\n      // Generate list of extensions to enable')
    edit(source, "src/dxvk/dxvk_instance.cpp", "      info.pApplicationInfo         = &appInfo;",
         '#ifdef DXVK_WSI_APPLE\n'
         '      if (extensionSet.supports(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME))\n'
         '        info.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;\n'
         '#endif\n      info.pApplicationInfo         = &appInfo;')
    edit(source, "src/dxvk/dxvk_adapter.cpp", "    extensionsEnabled.merge(m_extraExtensions);",
         '    extensionsEnabled.merge(m_extraExtensions);\n#ifdef DXVK_WSI_APPLE\n'
         '    if (m_deviceExtensions.supports("VK_KHR_portability_subset"))\n'
         '      extensionsEnabled.add("VK_KHR_portability_subset");\n#endif')
    edit(source, "src/util/util_env.cpp", "#ifdef __linux__",
         "#if defined(__APPLE__)\n#include <mach-o/dyld.h>\n#elif defined(__linux__)")
    edit(source, "src/util/util_env.cpp", "#elif defined(__linux__)\n    std::array<char, PATH_MAX> exePath = {};",
         "#elif defined(__APPLE__)\n    uint32_t size = 0;\n    _NSGetExecutablePath(nullptr, &size);\n"
         "    std::vector<char> path(size);\n    return _NSGetExecutablePath(path.data(), &size) == 0 ? path.data() : std::string();\n"
         "#elif defined(__linux__)\n    std::array<char, PATH_MAX> exePath = {};")
    edit(source, "src/util/util_env.cpp", "    ::pthread_setname_np(pthread_self(), posixName.data());",
         "#if defined(__APPLE__)\n    ::pthread_setname_np(posixName.data());\n"
         "#else\n    ::pthread_setname_np(pthread_self(), posixName.data());\n#endif")
    edit(source, "src/util/util_win32_compat.h", "#if defined(__unix__)", "#if defined(__unix__) || defined(__APPLE__)")
    edit(source, "src/util/util_math.h", "#include <cmath>", "#include <cmath>\n#include <stddef.h>")
    edit(source, "src/dxvk/dxvk_presenter.cpp", "#if defined(__ANDROID__)",
         "#if defined(DXVK_WSI_APPLE)", count=3)
    edit(source, "src/dxvk/dxvk_pipecache_file.h", "#include <fstream>",
         "#include <fstream>\n#include <limits>")
    edit(source, "src/dxvk/dxvk_pipecache_file.h",
         "      std::ifstream file(m_path, std::ios::binary);\n      if (!file)\n        return { };\n\n"
         "      std::vector<char> data((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());",
         "      std::ifstream file(m_path, std::ios::binary | std::ios::ate);\n"
         "      if (!file)\n        return { };\n\n"
         "      const std::streamoff bytes = file.tellg();\n"
         "      if (bytes < std::streamoff(sizeof(VkPipelineCacheHeaderVersionOne)) ||\n"
         "          uintmax_t(bytes) > std::vector<char>().max_size() ||\n"
         "          bytes > std::numeric_limits<std::streamsize>::max())\n        return { };\n\n"
         "      std::vector<char> data(static_cast<size_t>(bytes));\n"
         "      if (!file.seekg(0) || !file.read(data.data(), std::streamsize(bytes)))\n        return { };")
    device = "src/d3d9/d3d9_device.cpp"
    # DXVK's layered copy, blit and resolve shaders have a vertex-layer path.
    # ProcessVertices is the D3D9 path that still uses a geometry shader.
    edit(source, device, "    enabled.core.features.geometryShader = VK_TRUE;",
         "    enabled.core.features.geometryShader = supported.core.features.geometryShader;\n"
         "    if (!supported.core.features.geometryShader && !supported.vk12.shaderOutputLayer)\n"
         '      throw DxvkError("D3D9 Apple: layered meta operations need geometryShader or shaderOutputLayer");')
    edit(source, device, "    enabled.core.features.fillModeNonSolid = VK_TRUE;",
         "    enabled.core.features.fillModeNonSolid = supported.core.features.fillModeNonSolid;")
    edit(source, device, "    enabled.core.features.shaderCullDistance = VK_TRUE;",
         "    enabled.core.features.shaderCullDistance = supported.core.features.shaderCullDistance;")
    edit(source, device, "    return m_dxvkDevice->features().core.features.vertexPipelineStoresAndAtomics &&",
         "    return m_dxvkDevice->features().core.features.geometryShader &&\n"
         "           m_dxvkDevice->features().core.features.vertexPipelineStoresAndAtomics &&")
    edit(source, device, '        Logger::err("D3D9DeviceEx::ProcessVertices: SWVP emu unsupported (vertexPipelineStoresAndAtomics)");\n\n      return D3D_OK;',
         '        Logger::err("D3D9DeviceEx::ProcessVertices: required geometry or vertex storage features unavailable");\n\n'
         "      return D3DERR_NOTAVAILABLE;")
    edit(source, device, "    if (unlikely(ShouldRecord()))\n      return m_recorder->SetRenderState(State, Value);",
         "    if (State == D3DRS_FILLMODE && Value != D3DFILL_SOLID &&\n"
         "        !m_dxvkDevice->features().core.features.fillModeNonSolid) {\n"
         '      Logger::warn("D3D9 Apple: non-solid polygon fill unavailable");\n'
         "      return D3DERR_NOTAVAILABLE;\n    }\n\n"
         "    if (unlikely(ShouldRecord()))\n      return m_recorder->SetRenderState(State, Value);")
    split_shadow_descriptors(source, device)
    edit(source, "src/dxvk/dxvk_pipemanager.cpp",
         "    auto iter = m_shaderLibraries.emplace(\n      std::piecewise_construct,\n      std::tuple(),\n"
         "      std::tuple(m_device, this, key, layout));",
         "    auto iter = m_shaderLibraries.try_emplace(key, m_device, this, key, layout);")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="DXVK checkout with pinned submodules")
    parser.add_argument("--sdk", type=Path, required=True, help="Vulkan SDK macOS directory")
    parser.add_argument("--meson", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build/apple/dxvk")
    parser.add_argument("--jobs", type=int, default=8)
    args = parser.parse_args()

    output = args.build.resolve()
    source = output.with_name(output.name + "-source")
    pins = json.loads((ROOT / "dependencies-dxvk.json").read_text())
    prepare_source(pins, args.source.resolve(), source, platform="apple")
    apply_apple(source)
    # Share the feature-truthful MoltenVK path already validated on iOS.
    # Native robustness2 remains selected when the driver provides it.
    from d3d9_portability import apply_d3d9_portability
    apply_d3d9_portability(source)
    env = os.environ.copy()
    env["PATH"] = str(args.sdk.resolve() / "bin") + os.pathsep + env["PATH"]
    env["GIT_CEILING_DIRECTORIES"] = str(source.parent)
    settings = [
        "--buildtype=release", "-Denable_dxgi=false", "-Denable_d3d11=false",
        "-Denable_d3d10=false", "-Denable_d3d9=true", "-Denable_d3d8=false",
    ]
    if not (output / "build.ninja").exists():
        run([args.meson.resolve(), "setup", output, source, *settings], env=env)
    run(["ninja", "-C", output, "-j", args.jobs], env=env)
    library = output / "src/d3d9/libdxvk_d3d9.dylib"
    receipt = {"upstream": REVISION, "library_sha256": sha(library), "sdk": str(args.sdk.resolve())}
    receipt["portability_overlay_sha256"] = {
        name: sha(ROOT / name) for name in ("tools/d3d9_portability.py", "platform/apple/ios/d3d9_unbound.inc")
    }
    write(output / "receipt.json", json.dumps(receipt, indent=2) + "\n")
    print(library)


if __name__ == "__main__":
    main()
