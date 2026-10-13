#!/bin/bash

select_signing_identity() {
    local identity_file="$PROJECT_DIR/.local-signing-identity"
    if [[ "${CODE_SIGN_IDENTITY+x}" == x ]]; then
        SIGNING_IDENTITY="$CODE_SIGN_IDENTITY"
    elif [[ -f "$identity_file" ]]; then
        SIGNING_IDENTITY="$(cat "$identity_file")"
    else
        local available candidates count kind
        available="$(security find-identity -v -p codesigning)" || return 1
        SIGNING_IDENTITY=""
        for kind in 'Developer ID Application:' 'Apple Development:'; do
            candidates="$(printf '%s\n' "$available" | awk -v kind="$kind" 'index($0, kind) { print $2 }')"
            count="$(printf '%s\n' "$candidates" | awk 'NF { n++ } END { print n+0 }')"
            if [[ "$count" -gt 1 ]]; then
                printf '找到多個 %s 憑證，請用 CODE_SIGN_IDENTITY 指定簽署身分。\n' "$kind" >&2
                return 1
            elif [[ "$count" -eq 1 ]]; then
                SIGNING_IDENTITY="$candidates"
                break
            fi
        done
    fi
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        printf '找不到可用的簽署憑證，請用 CODE_SIGN_IDENTITY 指定身分；本機測試可明確指定 - 使用 ad hoc 簽章。\n' >&2
        return 1
    fi
    if [[ "$SIGNING_IDENTITY" == - ]]; then
        printf '使用 ad hoc 簽章：內容更新後，macOS 權限可能需要重新授權。\n' >&2
    fi
}

save_signing_identity() {
    if [[ "$SIGNING_IDENTITY" != - ]]; then
        printf '%s\n' "$SIGNING_IDENTITY" > "$PROJECT_DIR/.local-signing-identity"
    fi
}
