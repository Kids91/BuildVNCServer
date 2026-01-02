#!/bin/bash

set -ex

# 1. Khởi tạo mã nguồn
rm -rf libpng
git clone --depth 1 https://github.com/pnggroup/libpng.git
WORKING_DIR="$(pwd)/libpng"
OUTPUT_DIR="$(pwd)/output"

cd "$WORKING_DIR"

XCODE_DIR=$(xcode-select -p)
IOS_SYSROOT=$(xcrun --sdk iphoneos --show-sdk-path)

# Hàm build cho từng kiến trúc
build_arch() {
    local ARCH=$1
    echo "--- Đang build libpng cho $ARCH ---"
    
    rm -rf "build_$ARCH"
    mkdir -p "build_$ARCH"
    
    # SỬA ĐỔI: Thêm các flag để tắt hoàn toàn SHARED (dylib)
    cmake -G Xcode -B "build_$ARCH" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$IOS_SYSROOT" \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.5 \
        -DPNG_SHARED=OFF \
        -DPNG_STATIC=ON \
        -DPNG_TESTS=OFF \
        -DCMAKE_INSTALL_PREFIX="$(pwd)/install_$ARCH"
        # -DPNG_ARM_NEON=on \
        # -DARM_NEON=on \

    # Chỉ build target png_static
    xcodebuild build \
        -project "build_$ARCH/libpng.xcodeproj" \
        -target png_static \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        CODE_SIGNING_ALLOWED="NO" CODE_SIGNING_REQUIRED="NO" CODE_SIGN_IDENTITY="" \
        | (xcpretty || cat)

    # Cài đặt thủ công vì lệnh 'cmake --install' sẽ lỗi khi tìm kiếm dylib
    mkdir -p "install_$ARCH/lib"
    mkdir -p "install_$ARCH/include/libpng16"
    
    # Tìm file .a vừa build xong và copy vào thư mục install
    # Tên file có thể là libpng16.a hoặc libpng.a tùy version
    find "build_$ARCH/Release-iphoneos" -name "*.a" -exec cp {} "install_$ARCH/lib/" \;
    cp "$WORKING_DIR"/*.h "install_$ARCH/include/libpng16/"
    cp "build_$ARCH"/*.h "install_$ARCH/include/libpng16/" 2>/dev/null || true
}

# 2. Thực hiện build lần lượt
build_arch "arm64"
build_arch "arm64e"

# 3. Gộp thành Fat Binary
echo "--- Đang gộp libpng thành Fat Binary ---"
mkdir -p "$OUTPUT_DIR/lib"
mkdir -p "$OUTPUT_DIR/include"

# Tự động tìm tên file .a thực tế trong thư mục install_arm64
REAL_LIB_NAME=$(ls install_arm64/lib/*.a | xargs -n 1 basename | head -n 1)

if [ -z "$REAL_LIB_NAME" ]; then
    echo "Lỗi: Không tìm thấy file thư viện .a nào trong install_arm64/lib"
    exit 1
fi

echo "Phát hiện file thư viện: $REAL_LIB_NAME"

lipo -create \
    "install_arm64/lib/$REAL_LIB_NAME" \
    "install_arm64e/lib/$REAL_LIB_NAME" \
    -output "$OUTPUT_DIR/lib/$REAL_LIB_NAME"

# Tạo các link hoặc bản sao chuẩn để dễ sử dụng (libpng.a)
cp "$OUTPUT_DIR/lib/$REAL_LIB_NAME" "$OUTPUT_DIR/lib/libpng.a"

# 4. Copy headers
# Đảm bảo copy toàn bộ folder include đã chuẩn bị vào output
cp -R install_arm64/include/. "$OUTPUT_DIR/include/"

echo "--- Hoàn tất libpng! ---"
lipo -info "$OUTPUT_DIR/lib/libpng.a"