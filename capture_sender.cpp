// capture_sender.cpp
// Windows Graphics Capture helper that captures a window and publishes frames
// via a shared memory buffer named "LOVE_CAPTURE_SHARED_FRAME".
//
// Build (Developer Command Prompt for VS):
//   cl /std:c++20 /EHsc /permissive- capture_sender.cpp ^
//      /link windowsapp.lib d3d11.lib dxgi.lib user32.lib /OUT:build\capture_sender.exe
//
// Requires: Windows 10 1903+, Windows 10 SDK with Graphics Capture, x64.

#define UNICODE
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <d3d11.h>
#include <dxgi1_6.h>
#include <psapi.h>

#include <winrt/base.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <windows.graphics.capture.interop.h>
// Some SDKs lack a friendly projection name for IDirect3DDxgiInterfaceAccess;
// declare it explicitly to avoid ABI namespace differences across SDK versions.
#include <windows.graphics.directx.direct3d11.interop.h>
#ifndef __IDirect3DDxgiInterfaceAccess_INTERFACE_DEFINED__
struct __declspec(uuid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1")) IDirect3DDxgiInterfaceAccess : IUnknown {
    virtual HRESULT __stdcall GetInterface(GUID const& id, void** object) = 0;
};
#endif

#include <string>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <fstream>

using namespace winrt;
using namespace winrt::Windows::Graphics::Capture;
using namespace winrt::Windows::Graphics::DirectX;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;

// Shared memory layout (matches capture.lua)
#pragma pack(push, 1)
struct CaptureSharedFrame {
    uint32_t magic;       // 0xC0FFEE01
    uint32_t width;
    uint32_t height;
    uint32_t format;      // 0=RGBA, 1=BGRA
    uint32_t frame_number;
    uint64_t timestamp_us;
    uint32_t data_size;   // pixel data size
    uint32_t reserved;    // padding
    // uint8_t pixel_data[data_size];
};
#pragma pack(pop)

static constexpr uint32_t MAGIC = 0xC0FFEE01u;
static constexpr wchar_t SHM_NAME[] = L"LOVE_CAPTURE_SHARED_FRAME";
// Shared memory capacity is sized at runtime to the current capture resolution
// to avoid reserving a large fixed buffer (e.g., 64 MiB) when not needed.

// Import interop function
extern "C" HRESULT __stdcall CreateDirect3D11DeviceFromDXGIDevice(
    IDXGIDevice* dxgiDevice,
    IInspectable** graphicsDevice
);

// Utility: high-resolution timestamp in microseconds
static uint64_t now_us()
{
    static LARGE_INTEGER freq = []{ LARGE_INTEGER f; QueryPerformanceFrequency(&f); return f; }();
    LARGE_INTEGER t; QueryPerformanceCounter(&t);
    return static_cast<uint64_t>((t.QuadPart * 1000000ULL) / freq.QuadPart);
}

static std::wofstream g_log;
static void log_open()
{
    try {
        g_log.open(L"capture_sender.log", std::ios::out | std::ios::app);
        if (g_log) {
            g_log << L"[start] pid=" << GetCurrentProcessId() << L"\n";
        }
    } catch(...) {}
}
static void log_line(const std::wstring& s)
{
    if (g_log) {
        g_log << s << L"\n";
        g_log.flush();
    }
}

// Simple lower-case substring search (UTF-16 naive)
static std::wstring get_window_title(HWND hwnd)
{
    wchar_t buf[1024];
    int n = GetWindowTextW(hwnd, buf, 1023);
    if (n <= 0) return L"";
    return std::wstring(buf, buf + n);
}

// Find target window by title substring (case-insensitive). If empty, return foreground window.
static HWND find_window_by_title(const std::wstring& title_substr)
{
    // If no title provided, try to detect a PowerPoint slide show window by common title/class,
    // fall back to foreground window.
    std::wstring needle = title_substr;
    for (auto& ch : needle) ch = towlower(ch);
    struct EnumData { const std::wstring* needle; HWND result; bool prefer_ppt; } data{ &needle, nullptr, title_substr.empty() };
    EnumWindows([](HWND hwnd, LPARAM lp) -> BOOL {
        auto* d = reinterpret_cast<EnumData*>(lp);
        if (!IsWindowVisible(hwnd)) return TRUE;
        std::wstring title = get_window_title(hwnd);
        std::wstring lower = title;
        for (auto& ch : lower) ch = towlower(ch);
        if (d->prefer_ppt) {
            // Prefer PowerPoint Slide Show windows
            if (lower.find(L"powerpoint slide show") != std::wstring::npos) { d->result = hwnd; return FALSE; }
            return TRUE;
        }
        if (!d->needle->empty() && lower.find(*d->needle) != std::wstring::npos) { d->result = hwnd; return FALSE; }
        return TRUE;
    }, reinterpret_cast<LPARAM>(&data));
    if (data.result) return data.result;
    return GetForegroundWindow();
}

// Helper: get IDirect3DDevice from ID3D11Device
static winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice CreateWinRTDeviceFromD3DDevice(ID3D11Device* d3dDevice)
{
    winrt::com_ptr<IDXGIDevice> dxgiDevice;
    winrt::check_hresult(d3dDevice->QueryInterface(dxgiDevice.put()));
    winrt::com_ptr<IInspectable> inspectable;
    winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.get(), inspectable.put()));
    return inspectable.as<IDirect3DDevice>();
}

// Helper: get ID3D11Texture2D from IDirect3DSurface
template<typename T>
static winrt::com_ptr<T> GetDXGIInterfaceFromObject(winrt::Windows::Foundation::IInspectable const& object)
{
    winrt::com_ptr<IDirect3DDxgiInterfaceAccess> access = object.as<IDirect3DDxgiInterfaceAccess>();
    winrt::com_ptr<T> result;
    winrt::check_hresult(access->GetInterface(__uuidof(T), result.put_void()));
    return result;
}

// Memory diagnostics
static void log_memory_stats(ID3D11Device* d3d)
{
    // Process memory
    PROCESS_MEMORY_COUNTERS_EX pmc{};
    if (GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&pmc), sizeof(pmc))) {
        std::wstring line = L"proc_mem: WS=" + std::to_wstring(pmc.WorkingSetSize / (1024 * 1024)) +
                            L"MB, Private=" + std::to_wstring(pmc.PrivateUsage / (1024 * 1024)) + L"MB, PagedPool=" +
                            std::to_wstring(pmc.QuotaPagedPoolUsage / (1024 * 1024)) + L"MB";
        log_line(line);
    }

    // GPU memory via DXGI if available
    try {
        winrt::com_ptr<IDXGIDevice> dxgiDevice;
        if (SUCCEEDED(d3d->QueryInterface(dxgiDevice.put()))) {
            winrt::com_ptr<IDXGIAdapter> adapter;
            if (SUCCEEDED(dxgiDevice->GetAdapter(adapter.put()))) {
                winrt::com_ptr<IDXGIAdapter3> adapter3;
                if (SUCCEEDED(adapter->QueryInterface(adapter3.put()))) {
                    DXGI_QUERY_VIDEO_MEMORY_INFO local{};
                    DXGI_QUERY_VIDEO_MEMORY_INFO nonlocal{};
                    if (SUCCEEDED(adapter3->QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, &local)) &&
                        SUCCEEDED(adapter3->QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_NON_LOCAL, &nonlocal))) {
                        std::wstring line = L"gpu_mem: local_used=" + std::to_wstring(local.CurrentUsage / (1024 * 1024)) + L"MB/" +
                                            std::to_wstring(local.Budget / (1024 * 1024)) + L"MB, nonlocal_used=" +
                                            std::to_wstring(nonlocal.CurrentUsage / (1024 * 1024)) + L"MB/" +
                                            std::to_wstring(nonlocal.Budget / (1024 * 1024)) + L"MB";
                        log_line(line);
                    }
                }
            }
        }
    } catch(...) {
        // ignore
    }
}

int wmain(int argc, wchar_t** argv)
{
    winrt::init_apartment();
    log_open();

    // Parse --title argument (optional)
    std::wstring title;
    int pool_size = 1; // default single-buffer to minimize memory
    int memlog_every = 0; // log memory every N frames (0=disabled)
    for (int i = 1; i < argc; ++i)
    {
        std::wstring arg = argv[i];
        const std::wstring prefix = L"--title=";
        if (arg.rfind(prefix, 0) == 0) {
            title = arg.substr(prefix.size());
            if (!title.empty() && title.front() == L'"' && title.back() == L'"') {
                title = title.substr(1, title.size() - 2);
            }
            continue;
        }
        const std::wstring pool_prefix = L"--pool=";
        if (arg.rfind(pool_prefix, 0) == 0) {
            try {
                int value = std::stoi(arg.substr(pool_prefix.size()));
                if (value < 1) value = 1;
                if (value > 4) value = 4;
                pool_size = value;
            } catch(...) {}
            continue;
        }
        const std::wstring memlog_prefix = L"--memlog=";
        if (arg.rfind(memlog_prefix, 0) == 0) {
            try {
                int value = std::stoi(arg.substr(memlog_prefix.size()));
                if (value < 0) value = 0;
                if (value > 100000) value = 100000;
                memlog_every = value;
            } catch(...) {}
            continue;
        }
    }

    // Find target window
    HWND hwnd = find_window_by_title(title);
    if (!hwnd) {
        fwprintf(stderr, L"capture_sender: target window not found (title contains: '%s')\n", title.c_str());
        log_line(L"no target window");
        return 2;
    }
    {
        // Log chosen window title for debugging
        std::wstring chosen = get_window_title(hwnd);
        log_line(L"chosen window: " + chosen);
    }

    // Create D3D11 device/context
    winrt::com_ptr<ID3D11Device> d3d;
    winrt::com_ptr<ID3D11DeviceContext> ctx;
    D3D_FEATURE_LEVEL fl;
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
#if defined(_DEBUG)
    // flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif
    winrt::check_hresult(D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
        nullptr, 0, D3D11_SDK_VERSION, d3d.put(), &fl, ctx.put()));

    // Create WinRT device
    auto winrtDevice = CreateWinRTDeviceFromD3DDevice(d3d.get());

    // Log adapter information and initial memory
    try {
        winrt::com_ptr<IDXGIDevice> dxgiDevice;
        if (SUCCEEDED(d3d->QueryInterface(dxgiDevice.put()))) {
            winrt::com_ptr<IDXGIAdapter> adapter;
            if (SUCCEEDED(dxgiDevice->GetAdapter(adapter.put()))) {
                DXGI_ADAPTER_DESC1 desc{};
                winrt::com_ptr<IDXGIAdapter1> adapter1;
                if (SUCCEEDED(adapter->QueryInterface(adapter1.put()))) {
                    if (SUCCEEDED(adapter1->GetDesc1(&desc))) {
                        std::wstring name(desc.Description);
                        log_line(L"adapter: " + name + L", DedicatedVideoMemory=" + std::to_wstring(desc.DedicatedVideoMemory / (1024 * 1024)) + L"MB");
                    }
                }
                log_memory_stats(d3d.get());
            }
        }
    } catch(...) {}

    // Create GraphicsCaptureItem for HWND
    winrt::com_ptr<IGraphicsCaptureItemInterop> interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
    GraphicsCaptureItem item{ nullptr };
    winrt::check_hresult(interop->CreateForWindow(hwnd, winrt::guid_of<GraphicsCaptureItem>(), winrt::put_abi(item)));

    // Initial size
    auto size = item.Size();
    if (size.Width <= 0 || size.Height <= 0) {
        fwprintf(stderr, L"capture_sender: invalid capture size %dx%d\n", size.Width, size.Height);
        return 3;
    }

    // Create frame pool and session
    if (!GraphicsCaptureSession::IsSupported()) {
        log_line(L"GraphicsCaptureSession::IsSupported() == false");
    }
    auto pixelFormat = DirectXPixelFormat::B8G8R8A8UIntNormalized;
    // Pool size configurable via --pool (1..4)
    auto pool = Direct3D11CaptureFramePool::Create(winrtDevice, pixelFormat, pool_size, size);
    auto session = pool.CreateCaptureSession(item);
    session.IsCursorCaptureEnabled(true);
    session.IsBorderRequired(false);
    session.StartCapture();
    log_line(L"capture started (pool=" + std::to_wstring(pool_size) + L", memlog_every=" + std::to_wstring(memlog_every) + L")");

    // Shared memory setup sized to initial content
    const uint64_t initial_w = static_cast<uint64_t>(size.Width);
    const uint64_t initial_h = static_cast<uint64_t>(size.Height);
    const uint64_t bytes_per_pixel = 4;
    uint64_t needed = sizeof(CaptureSharedFrame) + (initial_w * initial_h * bytes_per_pixel);
    if (needed < 64) needed = 64; // minimum header space
    // Cap to 1 GiB to avoid pathological sizes
    if (needed > (1ull << 30)) needed = (1ull << 30);
    DWORD cap_low = static_cast<DWORD>(needed & 0xFFFFFFFFull);
    DWORD cap_high = static_cast<DWORD>((needed >> 32) & 0xFFFFFFFFull);
    HANDLE hMap = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, cap_high, cap_low, SHM_NAME);
    if (!hMap) {
        fprintf(stderr, "capture_sender: CreateFileMapping failed (%lu)\n", GetLastError());
        return 4;
    }
    void* view = MapViewOfFile(hMap, FILE_MAP_ALL_ACCESS, 0, 0, 0);
    if (!view) {
        fprintf(stderr, "capture_sender: MapViewOfFile failed (%lu)\n", GetLastError());
        CloseHandle(hMap);
        return 5;
    }
    auto* header = reinterpret_cast<CaptureSharedFrame*>(view);
    std::memset(view, 0, 64); // clear header
    header->magic = MAGIC;

    // Staging texture cache
    winrt::com_ptr<ID3D11Texture2D> staging;
    D3D11_TEXTURE2D_DESC stagingDesc{};
    ZeroMemory(&stagingDesc, sizeof(stagingDesc));

    std::atomic_uint32_t frameCounter{0};
    std::atomic_bool running{true};

    // Polling run loop: pull frames and monitor window
    int printed = 0;
    uint64_t frames_processed = 0;
    while (running) {
        if (!IsWindow(hwnd)) break;
        try {
            auto frame = pool.TryGetNextFrame();
            if (frame) {
                if (((printed++) % 60) == 0) log_line(L"frame arrived");
                auto newSize = frame.ContentSize();
                // If content size changed, recreate pool to match producer size
                if (newSize.Width > 0 && newSize.Height > 0 &&
                    (newSize.Width != (int)stagingDesc.Width || newSize.Height != (int)stagingDesc.Height)) {
                    pool.Recreate(winrtDevice, pixelFormat, pool_size, newSize);
                    staging = nullptr;
                    ZeroMemory(&stagingDesc, sizeof(stagingDesc));
                }

                {
                    auto surf = frame.Surface();
                    auto tex = GetDXGIInterfaceFromObject<ID3D11Texture2D>(surf);
                    if (tex) {
                        D3D11_TEXTURE2D_DESC desc{}; tex->GetDesc(&desc);
                    if (!staging || desc.Width != stagingDesc.Width || desc.Height != stagingDesc.Height) {
                        staging = nullptr;
                        stagingDesc.Width = desc.Width;
                        stagingDesc.Height = desc.Height;
                        stagingDesc.MipLevels = 1;
                        stagingDesc.ArraySize = 1;
                        stagingDesc.Format = desc.Format;
                        stagingDesc.SampleDesc = {1, 0};
                        stagingDesc.Usage = D3D11_USAGE_STAGING;
                        stagingDesc.BindFlags = 0;
                        stagingDesc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
                        stagingDesc.MiscFlags = 0;
                        winrt::check_hresult(d3d->CreateTexture2D(&stagingDesc, nullptr, staging.put()));
                        log_line(L"staging created: " + std::to_wstring(stagingDesc.Width) + L"x" + std::to_wstring(stagingDesc.Height));
                    }

                        ctx->CopyResource(staging.get(), tex.get());
                        D3D11_MAPPED_SUBRESOURCE mapped{};
                        if (SUCCEEDED(ctx->Map(staging.get(), 0, D3D11_MAP_READ, 0, &mapped))) {
                            const uint32_t w = stagingDesc.Width;
                            const uint32_t h = stagingDesc.Height;
                            const uint32_t bpp = 4;
                            const uint32_t rowBytes = w * bpp;
                            const size_t total = size_t(rowBytes) * h;
                            if ((printed % 120) == 0) {
                                log_line(L"mapped: RowPitch=" + std::to_wstring(mapped.RowPitch) + L" bytes, rowBytes=" + std::to_wstring(rowBytes));
                            }

                            // Check against the mapping capacity we allocated
                            const uint64_t capacity = needed;
                            if (sizeof(CaptureSharedFrame) + total <= capacity) {
                                header->width = w;
                                header->height = h;
                                header->format = 1;
                                header->data_size = 0;
                                uint8_t* dst = reinterpret_cast<uint8_t*>(header) + sizeof(CaptureSharedFrame);
                                const uint8_t* src = reinterpret_cast<const uint8_t*>(mapped.pData);
                                if (mapped.RowPitch == rowBytes) {
                                    std::memcpy(dst, src, total);
                                } else {
                                    for (uint32_t y = 0; y < h; ++y) {
                                        std::memcpy(dst + size_t(y) * rowBytes, src + size_t(y) * mapped.RowPitch, rowBytes);
                                    }
                                }
                                header->timestamp_us = now_us();
                                header->frame_number = frameCounter.fetch_add(1) + 1;
                                header->data_size = static_cast<uint32_t>(total);
                                header->magic = MAGIC;
                                if ((printed % 120) == 0) {
                                    log_line(L"write frame: " + std::to_wstring(w) + L"x" + std::to_wstring(h) + L", bytes=" + std::to_wstring(total));
                                }
                            } else {
                                // Not enough shared memory capacity for the new size; skip this frame.
                                if ((printed % 120) == 0) {
                                    log_line(L"frame too large for shared memory: " + std::to_wstring(w) + L"x" + std::to_wstring(h));
                                }
                            }
                            ctx->Unmap(staging.get(), 0);
                        }
                    }
                }
                // Explicitly close the frame to release underlying buffers immediately
                frame.Close();
                ++frames_processed;
                if (memlog_every > 0 && (frames_processed % static_cast<uint64_t>(memlog_every)) == 0) {
                    log_memory_stats(d3d.get());
                }
            } else {
                Sleep(5);
            }
        } catch (...) {
            // ignore and continue
        }
        Sleep(1);
    }

    // Cleanup
    session.Close();
    pool.Close();
    log_line(L"cleanup");

    if (view) UnmapViewOfFile(view);
    if (hMap) CloseHandle(hMap);

    return 0;
}
