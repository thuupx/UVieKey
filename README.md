# UVieKey

Bộ gõ tiếng Việt cho macOS, sử dụng engine `uvie-rs` viết bằng Rust.

## Tính năng

- **Telex & VNI**: đầy đủ hai kiểu gõ phổ biến.
- **Clipboard history**: lưu lịch sử copy, tự động tách đoạn theo delimiter (newline, comma, semicolon), giới hạn 1–99 entries.
- **Đặt dấu thanh theo chuẩn mới**: `hoas` → `hoá` (tùy chọn).
- **Tự động viết hoa đầu câu** sau `.!?` (tùy chọn).
- **Nhớ ngôn ngữ theo app**: tự động bật/tắt tiếng Việt cho từng ứng dụng.
- **Tự động tắt** khi detect bàn phím không Latin (Nhật, Hàn, Trung, Nga...).
- **Macro**: gõ tắt, ví dụ `mk` → `mình không`.
- **Fn tap toggle**: nhấn nhanh `Fn` để chuyển Anh/Việt.
- **AX mode**: hoạt động trong Spotlight và secure text fields.
- **Không Dock icon**: chỉ hiện trên menu bar.
- **Always on top**: cho phép bật/tắt chế độ luôn hiển thị trên các ứng dụng khác khi copy.

## Yêu cầu hệ thống

- macOS 13 Ventura trở lên
- Apple Silicon hoặc Intel (universal binary)

## Cài đặt

1. Tải `UVieKey-*-universal.dmg` từ [Releases](https://github.com/thuupx/uvie-rs/releases).
2. Mở DMG, kéo `UVieKey.app` vào thư mục `Applications`.
3. Mở app, cấp quyền **Accessibility** trong **System Settings → Privacy & Security → Accessibility**.
4. Icon `uvie` sẽ xuất hiện trên menu bar.

> Nếu macOS chặn vì Gatekeeper: vào **System Settings → Privacy & Security** và chọn **Open Anyway**.

## Cách dùng

- **Chuyển tiếng Việt**: click icon menu bar hoặc nhấn `Fn`.
- **Chọn kiểu gõ**: Telex / VNI trong Preferences.
- **Tạm dừng / thoát**: click icon menu bar.

## Phím tắt

| Phím | Chức năng |
| ------ | ----------- |
| `Fn` (tap) | Chuyển Anh / Việt |
| `Option + Backspace` | Xóa từ — OS xử lý, engine reset |
| `Shift + Backspace` | Xóa từng ký tự, giữ nguyên case |

## Build từ source

Requirements: Rust toolchain, Swift 5.9+, macOS SDK.

```bash
# Build Rust static library + Swift app
./build.sh

# Chạy
../.build/debug/UVieKey
```

Build release + package:

```bash
# Build Rust lib (universal)
cd ..
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin
lipo -create target/aarch64-apple-darwin/release/libuvie.a target/x86_64-apple-darwin/release/libuvie.a -output target/release/libuvie.a

# Build Swift app (universal)
cd UVieKey
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

Xem chi tiết kiến trúc và benchmark trong [README root](../README.md) và [`../src/ARCHITECT.md`](../src/ARCHITECT.md).

## License

MIT OR Apache-2.0
