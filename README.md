# UVieKey

Bộ gõ tiếng Việt nhanh, nhẹ và chính xác cho macOS, powered by engine `uvie-rs`.

## Tính năng

- **Telex & VNI**: đầy đủ hai kiểu gõ phổ biến.
- **Đặt dấu thanh theo chuẩn mới**: `hoas` → `hoá` (tùy chọn).
- **Viết tắt vần cuối (relaxed coda)**: `g` → `ng`, `h` → `nh` — gõ `đạg` thay `đặng`, `nhah` thay `nhạnh` (tùy chọn).
- **Tự động viết hoa đầu câu** sau `.!?` (tùy chọn).
- **Nhớ ngôn ngữ theo app**: tự động bật/tắt tiếng Việt cho từng ứng dụng.
- **Tự động tắt** khi detect bàn phím không Latin (Nhật, Hàn, Trung, Nga...).
- **Macro**: gõ tắt, ví dụ `mk` → `mình không`.
- **Fn tap toggle**: nhấn nhanh `Fn` để chuyển Anh/Việt.
- **Phím tắt tuỳ chỉnh**: cấu hình phím tắt toàn hệ thống để chuyển ngôn ngữ.
- **AX mode**: hoạt động trong Spotlight và secure text fields.
- **Kiểm tra cập nhật**: tự động kiểm tra 24 giờ/lần, nút kiểm tra thủ công trong tab Giới thiệu.
- **Không Dock icon**: chỉ hiện trên menu bar.

## Yêu cầu hệ thống

- macOS 13 Ventura trở lên
- Apple Silicon hoặc Intel (universal binary)

## Hiệu năng

- **DMG**: 1.7 MB (release pipeline, universal)
- **RAM**: ~30 MB (khi mở Setting window), ~14 MB (khi họat động background)
- **CPU**: ~0.3% khi gõ

## Cài đặt

1. Tải `UVieKey-*-universal.dmg` từ [Releases](https://github.com/thuupx/UVieKey/releases).
2. Mở DMG, kéo `UVieKey.app` vào thư mục `Applications`.
3. Mở app, làm theo onboarding — cấp quyền **Accessibility** (và **Input Monitoring** trên macOS 15+).
4. Icon `V` / `E` sẽ xuất hiện trên menu bar.

> Nếu macOS chặn vì Gatekeeper: vào **System Settings → Privacy & Security** và chọn **Open Anyway**.

## Cách dùng

- **Chuyển tiếng Việt / English**: click icon menu bar, nhấn `Fn`, hoặc phím tắt tuỳ chỉnh.
- **Chọn kiểu gõ**: Telex / VNI trong Cài đặt.
- **Cài đặt / Thoát**: click icon menu bar.

## Phím tắt

| Phím | Chức năng |
| ------ | ----------- |
| `Fn` (tap) | Chuyển Anh / Việt |
| Phím tắt tuỳ chỉnh | Chuyển Anh / Việt (cấu hình trong Cài đặt) |
| `Option + Backspace` | Xóa từ — OS xử lý, engine reset |
| `Shift + Backspace` | Xóa từng ký tự, giữ nguyên case |

## Cài đặt

App có 6 tab cài đặt:

| Tab | Chức năng |
| --- | --------- |
| **Tổng quan** | Bật/tắt engine, chọn Telex/VNI, nhớ ngôn ngữ từng app, tự động tắt khi non-Latin, khởi động cùng macOS, phím tắt |
| **Bàn phím** | Viết tắt vần cuối (g→ng, h→nh), viết hoa đầu câu |
| **Macro** | Bật/tắt macro văn bản, thêm/xóa macro |
| **Ứng dụng** | Quản lý danh sách app excluded, compound, Chromium |
| **Nâng cao** | Chính tả hiện đại, Quick Telex, Quick Start, chẩn đoán, gửi log |
| **Giới thiệu** | Phiên bản, kiểm tra cập nhật, link GitHub |

## Build từ source

Requirements: Rust toolchain, Swift 5.9+, macOS SDK.

```bash
# Build Swift app (lần đầu sẽ tự động fetch uvie-rs prebuilt library)
./build.sh

# Chạy
.build/debug/UVieKey
```

> Build từ source Rust local: set `UVIE_RS_DIR` trước khi chạy `build.sh`:
> ```bash
> UVIE_RS_DIR=/path/to/uvie-rs ./build.sh
> ```

Build release + package:

```bash
# Build Swift app (universal)
swift build --configuration release --arch arm64
swift build --configuration release --arch x86_64
lipo -create .build/arm64-apple-macosx/release/UVieKey .build/x86_64-apple-macosx/release/UVieKey -output .build/release/UVieKey

# Bundle .app
APP="UVieKey.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp .build/release/UVieKey "$APP/Contents/MacOS/UVieKey"
chmod +x "$APP/Contents/MacOS/UVieKey"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
```

## Kiến trúc mã nguồn

```
Sources/UVieKey/
├── App/                    # AppDelegate, entry point
├── Core/
│   ├── EventTap/           # CGEventTap handler (split theo chức năng)
│   │   ├── EventTap.swift          # lifecycle + state
│   │   ├── EventTap+Handle.swift   # main dispatcher + sub-handlers
│   │   ├── EventTap+AXMode.swift   # Accessibility text injection
│   │   ├── EventTap+SyntheticOutput.swift
│   │   ├── EventTap+Hotkey.swift   # Fn tap toggle
│   │   ├── EventTap+AutoCapitalize.swift
│   │   └── AppClassification.swift
│   ├── AXTextInjector.swift # AX-based text injection
│   ├── EngineBridge.swift   # Rust FFI bridge
│   └── KeyboardLayoutMonitor.swift
├── Features/               # InputMethodManager, MemoryManager, MacroManager
├── UI/
│   ├── Settings/           # SettingsWindow + Panes + Components
│   ├── MenuBar/            # MenuBarController + popover
│   ├── Onboarding/         # 3-step onboarding
│   └── Apps/               # Apps pane + icon cache + picker
└── Utils/                  # Logger, AppContextDetector, AppDefaults, etc.
```

## Release CI

Workflow `.github/workflows/release.yml` tự động build universal binary, sign, notarize, tạo DMG, và draft release.

Secrets cần thiết:

| Secret | Mô tả |
| -------- | ------- |
| `CERTIFICATE_P12_BASE64` | Developer ID Application certificate (base64) |
| `CERTIFICATE_PASSWORD` | Password file `.p12` |
| `KEYCHAIN_PASSWORD` | Password keychain tạm trong CI |
| `SIGNING_IDENTITY` | `Developer ID Application: Name (Team ID)` |
| `APPLE_ID` | Apple ID email |
| `APPLE_TEAM_ID` | Team ID 10 ký tự |
| `APPLE_APP_PASSWORD` | App-specific password từ appleid.apple.com |

## Engine

UVieKey sử dụng engine `uvie-rs` — Rust library, `no_std`/`no-alloc` compatible, zero deps.

Xem chi tiết kiến trúc và benchmark trong [README của uvie-rs](https://github.com/thuupx/uvie-rs).

## License

MIT OR Apache-2.0
