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
static constexpr size_t SHM_CAPACITY = size_t(64) * 1024 * 1024; // 64 MiB

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

int wmain(int argc, wchar_t** argv)
{
    winrt::init_apartment();
    log_open();

    // Parse --title argument (optional)
    std::wstring title;
    for (int i = 1; i < argc; ++i)
    {
        std::wstring arg = argv[i];
        const std::wstring prefix = L"--title=";
        if (arg.rfind(prefix, 0) == 0) {
            title = arg.substr(prefix.size());
            if (!title.empty() && title.front() == L'"' && title.back() == L'"') {
                title = title.substr(1, title.size() - 2);
            }
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
    auto pixelFormat = DirectXPixelFormat::B8G8R8A8UIntNormalized;
    auto pool = Direct3D11CaptureFramePool::Create(winrtDevice, pixelFormat, 2, size);
    auto session = pool.CreateCaptureSession(item);
    session.IsCursorCaptureEnabled(true);
    session.StartCapture();
    log_line(L"capture started");

    // Shared memory setup
    HANDLE hMap = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, static_cast<DWORD>(SHM_CAPACITY), SHM_NAME);
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
                    pool.Recreate(winrtDevice, pixelFormat, 2, newSize);
                    staging = nullptr;
                    ZeroMemory(&stagingDesc, sizeof(stagingDesc));
                }

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
                    }

                    ctx->CopyResource(staging.get(), tex.get());
                    D3D11_MAPPED_SUBRESOURCE mapped{};
                    if (SUCCEEDED(ctx->Map(staging.get(), 0, D3D11_MAP_READ, 0, &mapped))) {
                        const uint32_t w = stagingDesc.Width;
                        const uint32_t h = stagingDesc.Height;
                        const uint32_t bpp = 4;
                        const uint32_t rowBytes = w * bpp;
                        const size_t total = size_t(rowBytes) * h;

                        if (sizeof(CaptureSharedFrame) + total <= SHM_CAPACITY) {
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
                        }
                        ctx->Unmap(staging.get(), 0);
                    }
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
