#!/bin/bash

set -ex
realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

mkdir -p output
if [ -z "$SIMULATOR" ]; then
    # rm -rf Build-OpenSSL-cURL
    # git clone --depth=1 https://github.com/XXTouchNG/Build-OpenSSL-cURL.git # 7d215cdeb77a0b8ce56e9f07d487e869aec13f08
    # cd Build-OpenSSL-cURL
    # ./build.sh
    # cd -
    # cd BuildJPEG
    # ./build.sh
    # cd -
    # cd BuildLZO
    # ./build.sh
    # cd -
    # cd BuildPNG
    # ./build.sh
    # cd -
    cd BuildSASL
    # ./build.sh
    cd -
fi

rm -rf libvncserver
git clone --depth=1 https://github.com/LibVNC/libvncserver.git # 041ea576c3dddd6c7169935aaf8889673024fbfc
WORKING_DIR="$(dirname "$0")/libvncserver"

if [ ! -d "$WORKING_DIR" ]; then
    mkdir -p "$WORKING_DIR"
fi

cd "$WORKING_DIR"
WORKING_DIR=$(pwd)
if [ -f ../libvncserver.patch ]; then
    patch -s -p0 < ../libvncserver.patch
fi

git clean -fdx

SSL_ARCHIVE=$(ls -d ../Build-OpenSSL-cURL/archive/libcurl-*-ios-universal | head -n 1)

if [ -n "$SIMULATOR" ]; then
    cmake -G Xcode -B build \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_INSTALL_PREFIX="${WORKING_DIR}/../output" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES=arm64;arm64e \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.5 \
        -DWITH_EXAMPLES=OFF \
        -DWITH_TESTS=OFF \
        -DWITH_SDL=OFF \
        -DWITH_GTK=OFF \
        -DWITH_GNUTLS=OFF \
        -DWITH_SYSTEMD=OFF \
        -DWITH_FFMPEG=OFF \
        -DWITH_LZO=OFF \
        -DWITH_JPEG=OFF \
        -DWITH_PNG=OFF \
        -DWITH_OPENSSL=OFF \
        -DWITH_SASL=OFF
else
    cmake -G Xcode -B build \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_INSTALL_PREFIX="${WORKING_DIR}/../output" \
        -DCMAKE_SYSTEM_NAME=iOS \
        "-DCMAKE_OSX_ARCHITECTURES=arm64e" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.5 \
        -DWITH_EXAMPLES=OFF \
        -DWITH_TESTS=OFF \
        -DWITH_SDL=OFF \
        -DWITH_GTK=OFF \
        -DWITH_GNUTLS=OFF \
        -DWITH_SYSTEMD=OFF \
        -DWITH_FFMPEG=OFF \
        -DLZO_LIBRARIES="$(realpath ../BuildLZO/output/lib/liblzo2.a)" \
        -DLZO_INCLUDE_DIR="$(realpath ../BuildLZO/output/include)" \
        -DJPEG_LIBRARY="$(realpath ../BuildJPEG/output/lib/libturbojpeg.a)" \
        -DJPEG_INCLUDE_DIR="$(realpath ../BuildJPEG/output/include)" \
        -DPNG_LIBRARY="$(realpath ../BuildPNG/output/lib/libpng.a)" \
        -DPNG_PNG_INCLUDE_DIR="$(realpath ../BuildPNG/output/include)" \
        -DOPENSSL_LIBRARIES="$SSL_ARCHIVE/lib/iOS" \
        -DOPENSSL_CRYPTO_LIBRARY="$SSL_ARCHIVE/lib/iOS/libcrypto.a" \
        -DOPENSSL_SSL_LIBRARY="$SSL_ARCHIVE/lib/iOS/libssl.a" \
        -DOPENSSL_INCLUDE_DIR="$SSL_ARCHIVE/include" \
        -DLIBSASL2_LIBRARIES="$(realpath ../BuildSASL/output/lib/libsasl2.a)" \
        -DSASL2_INCLUDE_DIR="$(realpath ../BuildSASL/output/include)"
fi

cd build
if [ -f ../../libvncserver-build.patch ]; then
    patch include/rfb/rfbconfig.h -s -p0 < ../../libvncserver-build.patch
fi
cd -

PLATFORM_NAME="iOS"
DESTINATION="generic/platform=iOS"

# Kiểm tra xem xcpretty có tồn tại không
if command -v xcpretty &> /dev/null; then
    PRETTY="xcpretty"
else
    PRETTY="cat"
fi

xcodebuild clean build \
    -project build/LibVNCServer.xcodeproj \
    -scheme ALL_BUILD \
    -configuration Release \
    -destination "$DESTINATION" \
    -UseModernBuildSystem=YES \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED="NO" \
    STRIP_INSTALLED_PRODUCT=NO COPY_PHASE_STRIP=NO UNSTRIPPED_PRODUCT=NO \
    | $PRETTY

cd build
if [ -n "$SIMULATOR" ]; then
    ln -s Release-iphonesimulator Release
    export PLATFORM_NAME="iphonesimulator"
    export EFFECTIVE_PLATFORM_NAME="-iphonesimulator"
    cmake -DCMAKE_INSTALL_PREFIX="$(realpath ../../output)" \
        -P cmake_install.cmake
else
    ln -s Release-iphoneos Release
    cmake -DCMAKE_INSTALL_PREFIX="$(realpath ../../output)" \
        -P cmake_install.cmake
fi

read -p "Nhấn [Enter] để tiếp tục..."

# cd "$WORKING_DIR/.."
# mkdir -p dist
# mkdir -p dist/lib
# mkdir -p dist/include
# if [ -z "$SIMULATOR" ]; then
    ## lipo -thin arm64 Build-OpenSSL-cURL/openssl/iOS/lib/libcrypto.a -output dist/lib/libcrypto.a
    ## lipo -thin arm64 Build-OpenSSL-cURL/openssl/iOS/lib/libssl.a -output dist/lib/libssl.a
#     cp -r $SSL_ARCHIVE/lib/iOS/libcrypto.a dist/lib/libcrypto.a
#     cp -r $SSL_ARCHIVE/lib/iOS/libssl.a dist/lib/libssl.a
#     cp -r $SSL_ARCHIVE/lib/iOS/include/* dist/include
#     cp BuildJPEG/output/lib/libjpeg.a dist/lib/libjpeg.a
#     cp BuildJPEG/output/lib/libturbojpeg.a dist/lib/libturbojpeg.a
#     cp -r BuildJPEG/output/include/* dist/include
#     cp BuildLZO/output/lib/liblzo2.a dist/lib/liblzo2.a
#     cp -r BuildLZO/output/include/* dist/include
#     cp BuildPNG/output/lib/libpng18.a dist/lib/libpng18.a
#     cp BuildPNG/output/lib/libpng18.a dist/lib/libpng.a
#     cp -r BuildPNG/output/include/* dist/include
#     cp BuildSASL/output/lib/libsasl2.a dist/lib/libsasl2.a
#     cp -r BuildSASL/output/include/* dist/include
# fi
cp output/lib/libvncserver.a dist/lib/libvncserver.a
cp output/lib/libvncclient.a dist/lib/libvncclient.a
cp -r output/include/* dist/include
