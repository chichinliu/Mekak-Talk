#!/bin/bash
set -euo pipefail
TALK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TALK_RUNTIME="$TALK_ROOT/.build/transcribe-runtime"
TALK_SOURCE="$TALK_RUNTIME/source"
TALK_COMMIT=f1dcd15858c4bbba87ca97862b4e448b2cf15b8f
TALK_CMAKE="${TALK_CMAKE_BINARY:-$(command -v cmake || true)}"
if [[ -z "$TALK_CMAKE" && -x "$TALK_ROOT/.build/whisper-runtime/tooling/bin/cmake" ]]; then TALK_CMAKE="$TALK_ROOT/.build/whisper-runtime/tooling/bin/cmake"; fi
if [[ -z "$TALK_CMAKE" ]]; then printf '建置本機辨識引擎需要 CMake。\n' >&2; exit 1; fi
if [[ ! -d "$TALK_SOURCE/.git" ]]; then
    git clone https://github.com/handy-computer/transcribe.cpp.git "$TALK_SOURCE"
    git -C "$TALK_SOURCE" checkout --quiet "$TALK_COMMIT"
fi
if [[ "$(git -C "$TALK_SOURCE" rev-parse HEAD)" != "$TALK_COMMIT" ]]; then
    printf 'Qwen3-ASR 引擎原始碼版本不符，請檢查建置快取。\n' >&2; exit 1
fi
"$TALK_CMAKE" -S "$TALK_SOURCE" -B "$TALK_RUNTIME/build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DBUILD_SHARED_LIBS=OFF -DGGML_BACKEND_DL=OFF \
    -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_METAL_EMBED_LIBRARY=ON
"$TALK_CMAKE" --build "$TALK_RUNTIME/build" --target transcribe-cli --parallel 6
TALK_BINARY="$(find "$TALK_RUNTIME/build" -type f -name transcribe-cli -perm -u+x | head -1)"
if [[ -z "$TALK_BINARY" ]]; then printf '找不到 Qwen3-ASR 引擎執行檔。\n' >&2; exit 1; fi
if /usr/bin/otool -L "$TALK_BINARY" | /usr/bin/grep -E '/opt/homebrew|/usr/local|@rpath'; then
    printf 'Qwen3-ASR 引擎仍依賴外部函式庫，停止打包。\n' >&2; exit 1
fi
cp "$TALK_BINARY" "$TALK_RUNTIME/transcribe-cli"
