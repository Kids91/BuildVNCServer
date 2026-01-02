#!/bin/zsh

set -ex

# 1. Khởi tạo
rm -rf cyrus-sasl output
git clone --depth=1 https://github.com/cyrusimap/cyrus-sasl.git
WORKING_DIR="$(pwd)/cyrus-sasl"
FINAL_OUTPUT="$(pwd)/output"
mkdir -p "$FINAL_OUTPUT/lib" "$FINAL_OUTPUT/include/sasl"

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

XCODE_DIR=$(xcode-select -p)
SDK_PATH="${XCODE_DIR}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"

unsetopt NOMATCH

# Tìm thư mục và lấy kết quả đầu tiên

CHECK_OPENSSL_PATH="$(realpath ..)/Build-OpenSSL-cURL/archive"

OPENSSL_PATH=$(ls -d ${CHECK_OPENSSL_PATH}/libcurl-*-ios-universal 2>/dev/null | head -n 1)

# Bật lại chế độ NOMATCH (tùy chọn)
setopt NOMATCH
echo "✅ Đã tìm thấy OpenSSL tại: $OPENSSL_PATH"

build_arch() {
    local ARCH=$1
    echo "--- Building SASL for $ARCH ---"
    
    cd "$WORKING_DIR"
    # Dọn dẹp source nhưng không ảnh hưởng đến folder cài đặt bên ngoài
    git clean -fdx
    ./autogen.sh

    # 1. Thiết lập trình biên dịch từ Xcode
    export CC="$(xcrun --sdk iphoneos -f clang)"
    export CPP="$(xcrun --sdk iphoneos -f clang) -E"
    
    # 2. Thiết lập Flags
    export CFLAGS="-arch $ARCH -miphoneos-version-min=14.5 -isysroot $SDK_PATH -I$OPENSSL_PATH/include"
    export LDFLAGS="-arch $ARCH -isysroot $SDK_PATH -L$OPENSSL_PATH/lib/iOS"
    export CPPFLAGS="-DHAVE_STRUCT_SOCKADDR_STORAGE=1"

    # 3. Thư mục cài đặt tạm (ĐƯA RA NGOÀI WORKING_DIR)
    local TEMP_DEST="$(dirname "$WORKING_DIR")/temp_install_$ARCH"
    rm -rf "$TEMP_DEST" # Xóa bản cũ của riêng kiến trúc này nếu có
    mkdir -p "$TEMP_DEST"

    # 4. Lệnh Configure QUAN TRỌNG nhất
    # Thêm ac_cv để tránh lỗi sockaddr_storage
    # Thêm --host và --build để ép chế độ cross-compile
    ac_cv_type_struct_sockaddr_storage=yes \
    ac_cv_type_sockaddr_storage=yes \
    ac_cv_header_sys_socket_h=yes \
    ./configure \
        --host=arm-apple-darwin \
        --build=x86_64-apple-darwin \
        --prefix="/" \
        --disable-shared \
        --enable-static \
        --with-openssl="$OPENSSL_PATH" \
        --with-pam=no \
        --with-saslauthd=no \
        --disable-gssapi \
        --disable-otp \
        --disable-digest \
        --disable-utils \
        --disable-crypto-compat \
        --disable-macos-framework

    # 5. Biên dịch và Cài đặt
    for dir in include common sasldb plugins lib; do
        echo "--- Processing $dir ---"
        make -C $dir -j$(sysctl -n hw.ncpu)
        # Cài đặt vào thư mục tạm nằm ngoài folder git
        make -C $dir install DESTDIR="$TEMP_DEST" || true
    done
}

build_arch_e() {
    local ARCH=$1
    local HOST="$ARCH-apple-darwin"
    echo "--- Building SASL for $ARCH ---"
    cd "$WORKING_DIR"
    git clean -fdx
    ./autogen.sh

    export CC="$(xcrun --sdk iphoneos -f clang)"
    export CPP="$(xcrun --sdk iphoneos -f clang) -E"
    export CFLAGS="-arch $ARCH -miphoneos-version-min=14.5 -isysroot $SDK_PATH -I$OPENSSL_PATH/include"
    export LDFLAGS="-arch $ARCH -isysroot $SDK_PATH -L$OPENSSL_PATH/lib/iOS"
    
    local TEMP_DEST="$(dirname "$WORKING_DIR")/temp_install_$ARCH"
    rm -rf "$TEMP_DEST"
    mkdir -p "$TEMP_DEST"

    # Fix lỗi sockaddr_storage qua CPPFLAGS
    export CPPFLAGS="-DHAVE_STRUCT_SOCKADDR_STORAGE=1 -DPLUGINDIR=\\\"/usr/lib/sasl2\\\" -DCONFIGDIR=\\\"/etc/sasl2\\\""

    ./configure \
        --host="$HOST" \
        --build=x86_64-apple-darwin \
        --prefix="/" \
        --enable-static \
        --disable-shared \
        --with-openssl="$OPENSSL_PATH" \
        --with-dlopen=no \
        --with-pam=no \
        --with-saslauthd=no \
        --disable-gssapi \
        --disable-otp \
        --disable-digest \
        --disable-srp \
        --disable-ntlm \
        --disable-macos-framework \
        --with-staticsasl \
        --with-static-plugin=plain,anonymous

    # Thay vì sed phức tạp, ta build theo đúng thứ tự phụ thuộc
    echo "--- Compiling components ---"
    make -C include
    make -C common -j$(sysctl -n hw.ncpu)
    # Build plugins trước để có các file .o
    make -C plugins -j$(sysctl -n hw.ncpu) 
    
    # Tại thư mục lib, nếu Makefile bị lỗi 'ar', ta sẽ build thủ công thư viện .a
    cd lib
    make -j$(sysctl -n hw.ncpu) || true # Kệ nó lỗi ar, ta sẽ tự làm
    
    echo "--- Manually creating static library for $ARCH ---"
    # Gom tất cả object files từ lib, common và plugins vào một file .a duy nhất
    ar cr libsasl2.a *.o ../common/*.o ../plugins/plain.o ../plugins/anonymous.o
    ranlib libsasl2.a
    
    # Cài đặt thủ công vào TEMP_DEST
    mkdir -p "$TEMP_DEST/lib" "$TEMP_DEST/include/sasl"
    cp libsasl2.a "$TEMP_DEST/lib/"
    cd ..
    cp include/*.h "$TEMP_DEST/include/sasl/"
}

# 2. Thực hiện build
# build_arch "arm64"
# build_arch_e "arm64e"

# 3. Gộp thành Fat Binary (Lipo)
echo "--- Merging SASL Fat Binary ---"
PARENT_DIR="$(dirname "$WORKING_DIR")"

# lipo -create \
#     "$PARENT_DIR/temp_install_arm64/lib/libsasl2.a" \
#     "$PARENT_DIR/temp_install_arm64e/lib/libsasl2.a" \
#     -output "$FINAL_OUTPUT/lib/libsasl2.a"

# Copy headers (chỉ cần lấy từ 1 kiến trúc)
cp -R "$PARENT_DIR/temp_install_arm64/lib/libsasl2.a" "$FINAL_OUTPUT/lib/libsasl2.a"
cp -R "$PARENT_DIR/temp_install_arm64/include/sasl/"*.h "$FINAL_OUTPUT/include/sasl/"

# 5. Kiểm tra kết quả
echo "--- SASL Build Finished ---"
lipo -info "$FINAL_OUTPUT/lib/libsasl2.a"
