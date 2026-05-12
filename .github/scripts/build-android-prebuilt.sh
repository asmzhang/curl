#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: $0 <source-root> <abi> <android-platform> <openssl-root> <curl-version> <output-root>" >&2
  exit 1
fi

SOURCE_ROOT="$1"
ABI="$2"
ANDROID_PLATFORM="$3"
OPENSSL_ROOT="$4"
CURL_VERSION="$5"
OUTPUT_ROOT="$6"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SOURCE_ROOT}" && pwd)"
BUILD_DIR="${REPO_ROOT}/build-android-${ABI}"
INSTALL_DIR="${BUILD_DIR}/install"
CURL_PACKAGE_DIR="${OUTPUT_ROOT}/curl/${CURL_VERSION}/${ABI}"
OPENSSL_PACKAGE_DIR="${OUTPUT_ROOT}/openssl/${CURL_OPENSSL_VERSION}/${ABI}"

resolve_openssl_abi_dir() {
  local root="$1"
  local abi="$2"
  local -a candidates=(
    "${root}/${abi}"
    "${root}/${CURL_OPENSSL_VERSION}/${abi}"
    "${root}/openssl/${CURL_OPENSSL_VERSION}/${abi}"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}/include/openssl/ssl.h" && -f "${candidate}/lib/libssl.a" && -f "${candidate}/lib/libcrypto.a" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  echo "failed to locate OpenSSL prebuilts for ABI ${abi} under ${root}" >&2
  return 1
}

OPENSSL_ABI_DIR="$(resolve_openssl_abi_dir "${OPENSSL_ROOT}" "${ABI}")"
OPENSSL_INCLUDE_DIR="${OPENSSL_ABI_DIR}/include"
OPENSSL_SSL_LIBRARY="${OPENSSL_ABI_DIR}/lib/libssl.a"
OPENSSL_CRYPTO_LIBRARY="${OPENSSL_ABI_DIR}/lib/libcrypto.a"

rm -rf "${BUILD_DIR}"
mkdir -p "${CURL_PACKAGE_DIR}" "${OPENSSL_PACKAGE_DIR}"

cmake -S "${REPO_ROOT}" -B "${BUILD_DIR}" -G Ninja \
  -DANDROID_ABI="${ABI}" \
  -DANDROID_PLATFORM="android-${ANDROID_PLATFORM}" \
  -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_STATIC_LIBS=ON \
  -DBUILD_TESTING=OFF \
  -DBUILD_CURL_EXE=OFF \
  -DBUILD_LIBCURL_DOCS=OFF \
  -DBUILD_MISC_DOCS=OFF \
  -DENABLE_CURL_MANUAL=OFF \
  -DCURL_DISABLE_INSTALL=OFF \
  -DCURL_USE_OPENSSL=ON \
  -DCURL_ENABLE_SSL=ON \
  -DCURL_USE_MBEDTLS=OFF \
  -DCURL_USE_WOLFSSL=OFF \
  -DHTTP_ONLY=ON \
  -DCURL_ZLIB=OFF \
  -DCURL_BROTLI=OFF \
  -DCURL_ZSTD=OFF \
  -DCURL_USE_LIBPSL=OFF \
  -DCURL_CA_SEARCH_SAFE=OFF \
  -DOPENSSL_USE_STATIC_LIBS=ON \
  -DOPENSSL_ROOT_DIR="${OPENSSL_ABI_DIR}" \
  -DOPENSSL_INCLUDE_DIR="${OPENSSL_INCLUDE_DIR}" \
  -DOPENSSL_SSL_LIBRARY="${OPENSSL_SSL_LIBRARY}" \
  -DOPENSSL_CRYPTO_LIBRARY="${OPENSSL_CRYPTO_LIBRARY}"

cmake --build "${BUILD_DIR}" --target libcurl_static
cmake --install "${BUILD_DIR}"

mkdir -p "${CURL_PACKAGE_DIR}/include" "${CURL_PACKAGE_DIR}/lib"
cp -R "${INSTALL_DIR}/include/." "${CURL_PACKAGE_DIR}/include/"
cp "${INSTALL_DIR}/lib/libcurl.a" "${CURL_PACKAGE_DIR}/lib/"

cp -R "${OPENSSL_ABI_DIR}/." "${OPENSSL_PACKAGE_DIR}/"

{
  echo "curl_version=${CURL_VERSION}"
  echo "openssl_version=${CURL_OPENSSL_VERSION}"
  echo "android_abi=${ABI}"
  echo "android_platform=android-${ANDROID_PLATFORM}"
  echo "source_commit=${GITHUB_SHA:-unknown}"
} > "${OUTPUT_ROOT}/BUILD_INFO-${ABI}.txt"
