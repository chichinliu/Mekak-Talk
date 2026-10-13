#!/bin/bash
set -euo pipefail
TALK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TALK_RUNTIME="$TALK_ROOT/.build/whisper-runtime"
TALK_SOURCE="$TALK_RUNTIME/source"
TALK_COMMIT=306c88f4d1286aec1bf96e544632897886af5501
TALK_CMAKE="${TALK_CMAKE_BINARY:-$(command -v cmake || true)}"
if [[ -z "$TALK_CMAKE" && -x "$TALK_RUNTIME/tooling/bin/cmake" ]]; then TALK_CMAKE="$TALK_RUNTIME/tooling/bin/cmake"; fi
if [[ -z "$TALK_CMAKE" ]]; then printf '建置本機辨識引擎需要 CMake。\n' >&2; exit 1; fi
if [[ ! -d "$TALK_SOURCE/.git" ]]; then
    git clone --depth 1 --branch v1.9.2 https://github.com/ggml-org/whisper.cpp.git "$TALK_SOURCE"
fi
if [[ "$(git -C "$TALK_SOURCE" rev-parse HEAD)" != "$TALK_COMMIT" ]]; then
    printf 'Whisper 引擎原始碼版本不符，請檢查建置快取。\n' >&2; exit 1
fi
"$TALK_CMAKE" -S "$TALK_SOURCE" -B "$TALK_RUNTIME/build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DBUILD_SHARED_LIBS=OFF -DGGML_BACKEND_DL=OFF \
    -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_METAL_EMBED_LIBRARY=ON \
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF -DWHISPER_CURL=OFF
"$TALK_CMAKE" --build "$TALK_RUNTIME/build" --target whisper-cli --parallel 6
if /usr/bin/otool -L "$TALK_RUNTIME/build/bin/whisper-cli" | /usr/bin/grep -E '/opt/homebrew|/usr/local|@rpath'; then
    printf 'Whisper 引擎仍依賴外部函式庫，停止打包。\n' >&2; exit 1
fi
