#!/bin/bash

set -ex

# 1. Tải và giải nén
rm -rf lzo-2.10 lzo-2.10.tar.gz
curl -L https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz -o lzo-2.10.tar.gz
tar xvf lzo-2.10.tar.gz

WORKING_DIR="$(pwd)/lzo-2.10"
OUTPUT_DIR="$(pwd)/../output"
cd "$WORKING_DIR"

XCODE_DIR=$(xcode-select -p)
IOS_SYSROOT=$(xcrun --sdk iphoneos --show-sdk-path)

build_arch() {
    local ARCH=$1
    echo "--- Đang build LZO cho $ARCH ---"
    
    rm -rf "build_$ARCH"
    mkdir -p "build_$ARCH"
    
    cmake -G Xcode -B "build_$ARCH" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$IOS_SYSROOT" \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.5 \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_INSTALL_PREFIX="$(pwd)/install_$ARCH"

    # SỬA TẠI ĐÂY: Dùng -alltargets để Xcode tự tìm target có sẵn
    # Hoặc nếu bạn muốn dùng scheme, hãy dùng 'lzo_static' (tên phổ biến khác)
    # Ở đây chúng ta dùng giải pháp an toàn nhất cho Xcode project của LZO:
    xcodebuild build \
        -project "build_$ARCH/lzo.xcodeproj" \
        -alltargets \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        CODE_SIGNING_ALLOWED="NO" CODE_SIGNING_REQUIRED="NO" CODE_SIGN_IDENTITY="" \
        | (xcpretty || cat)

    # Sau khi build xong, file .a sẽ nằm trong Release-iphoneos/
    # Chúng ta chạy install để gom file về thư mục install_$ARCH
    cmake --install "build_$ARCH" --config Release
}

# 2. Thực hiện build
build_arch "arm64"
build_arch "arm64e"

# 3. Gộp thành Fat Binary
echo "--- Đang gộp LZO thành Fat Binary ---"
mkdir -p "$OUTPUT_DIR/lib"
mkdir -p "$OUTPUT_DIR/include/lzo"

lipo -create \
    "install_arm64/lib/liblzo2.a" \
    "install_arm64e/lib/liblzo2.a" \
    -output "$OUTPUT_DIR/lib/liblzo2.a"

# 4. Copy headers
cp -R install_arm64/include/lzo/. "$OUTPUT_DIR/include/lzo/"

echo "--- Hoàn tất LZO! ---"
lipo -info "$OUTPUT_DIR/lib/liblzo2.a"