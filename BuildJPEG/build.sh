#!/bin/bash

set -ex

# Setup Paths
ROOT_DIR="$(pwd)"
WORKING_DIR="$ROOT_DIR/libjpeg-turbo"
OUTPUT_DIR="$ROOT_DIR/output"

# Ensure source exists
if [ ! -d "$WORKING_DIR" ]; then
    echo "Error: libjpeg-turbo source directory not found at $WORKING_DIR"
    exit 1
fi

cd "$WORKING_DIR"

# Tooling Check
PRETTY="cat"
if command -v xcpretty &> /dev/null; then PRETTY="xcpretty"; fi

build_arch() {
    local ARCH=$1
    echo "--- Building for $ARCH ---"
    
    local BUILD_DIR="$WORKING_DIR/build_$ARCH"
    local INSTALL_DIR="$WORKING_DIR/install_$ARCH"
    
    rm -rf "$BUILD_DIR" "$INSTALL_DIR"
    mkdir -p "$BUILD_DIR"
    
    # Configure with CMake
    cmake -G Xcode -B "$BUILD_DIR" \
          -DCMAKE_SYSTEM_NAME=iOS \
          -DCMAKE_OSX_SYSROOT=iphoneos \
          -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
          -DCMAKE_OSX_DEPLOYMENT_TARGET=14.5 \
          -DENABLE_SHARED=0 \
          -DWITH_SIMD=1 \
          -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"

    # Build Static Targets
    xcodebuild build -project "$BUILD_DIR/libjpeg-turbo.xcodeproj" \
        -scheme jpeg-static -configuration Release \
        -destination 'generic/platform=iOS' \
        CODE_SIGNING_ALLOWED="NO" CODE_SIGNING_REQUIRED="NO" | $PRETTY

    xcodebuild build -project "$BUILD_DIR/libjpeg-turbo.xcodeproj" \
        -scheme turbojpeg-static -configuration Release \
        -destination 'generic/platform=iOS' \
        CODE_SIGNING_ALLOWED="NO" CODE_SIGNING_REQUIRED="NO" | $PRETTY

    # Install to temporary local folder
    cmake --install "$BUILD_DIR" --config Release --component lib
    cmake --install "$BUILD_DIR" --config Release --component headers
}

# 1. Execute Build for both architectures
build_arch "arm64"
build_arch "arm64e"

# 2. Prepare Final Output Directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/lib"
mkdir -p "$OUTPUT_DIR/include"

# 3. Lipo Combine into Fat Binaries
echo "--- Creating Fat Binaries ---"
xcrun -sdk iphoneos lipo -create \
    "install_arm64/lib/libjpeg.a" \
    "install_arm64e/lib/libjpeg.a" \
    -output "$OUTPUT_DIR/lib/libjpeg.a"

xcrun -sdk iphoneos lipo -create \
    "install_arm64/lib/libturbojpeg.a" \
    "install_arm64e/lib/libturbojpeg.a" \
    -output "$OUTPUT_DIR/lib/libturbojpeg.a"

# 4. Consolidate Headers (Critical for LibVNCServer)
echo "--- Consolidating Headers ---"

# Tạo thư mục include nếu chưa có
mkdir -p "$OUTPUT_DIR/include"

# 1. Copy từ thư mục source/src (Nơi chứa jpeglib.h, jmorecfg.h, v.v.)
if [ -d "$WORKING_DIR/src" ]; then
    echo "Phát hiện file trong thư mục src/..."
    cp "$WORKING_DIR"/src/*.h "$OUTPUT_DIR/include/" 2>/dev/null || true
fi

# 2. Copy từ thư mục gốc (Dự phòng)
cp "$WORKING_DIR"/*.h "$OUTPUT_DIR/include/" 2>/dev/null || true

# 3. Tìm và copy các file header được tạo ra trong quá trình build (như jconfig.h)
# Chúng ta tìm trong build_arm64 vì arm64 và arm64e có config giống nhau
find "build_arm64" -name "*.h" -exec cp {} "$OUTPUT_DIR/include/" \; 2>/dev/null || true

# 4. Kiểm tra cuối cùng
if [ -f "$OUTPUT_DIR/include/jpeglib.h" ]; then
    echo "--- SUCCESS: jpeglib.h đã được tìm thấy tại $OUTPUT_DIR/include ---"
else
    echo "--- FATAL ERROR: Vẫn không tìm thấy jpeglib.h! ---"
    exit 1
fi
