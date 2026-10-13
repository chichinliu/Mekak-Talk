# Hyday Talk

Hyday Talk 是一款原生 macOS 語音輸入工具，使用者在任何 App 中按下 fn 即可開始說話，再按一次 fn 完成，辨識並整理後的文字會插入原本的游標位置

本專案以 SwiftUI、AppKit、AVAudioEngine 與 Speech 開發，支援 macOS 14 以上，不依賴 Electron 或第三方 Swift 套件

## 主要功能

- **聽寫**：將語音轉為文字並插入目前的輸入框；找不到輸入框或輸入位置已變更時，自動複製文字
- **翻譯**：說話後直接輸出指定語言的譯文
- **文字提問**：以語音對選取文字下達指示，結果顯示於浮動面板供複製
- **文字整理**：補上標點、刪除口語贅字、依前後文修正同音錯字，並自動將列舉事項排成編號列表
- **個人詞典**：設定人名、品牌與術語的替換規則，並可從使用者對插入文字的修正中自動學習專有名稱
- **洞察**：統計口述字數、節省時間、口述速度、使用時段與常用 App

## 系統需求

| 項目 | 需求 |
| --- | --- |
| 作業系統 | macOS 14 以上 |
| 處理器 | Apple Silicon |
| 建置工具 | Xcode Command Line Tools、Swift 5.9 以上、CMake |
| 本機文字 AI（選用） | Ollama 與已下載的文字模型 |

## 建置與執行

```bash
bash scripts/build-app.sh
open 'dist/Hyday Talk.app'
```

建置前請關閉權限指引並完全結束 Hyday Talk，建置腳本會拒絕覆寫執行中的 App

建置腳本會依序選擇可用的 Developer ID Application 或 Apple Development 憑證，並將簽署身分保存於不納入版本控制的 `.local-signing-identity`，後續建置沿用同一身分以維持系統權限授權，亦可透過 `CODE_SIGN_IDENTITY` 環境變數指定憑證；本機臨時測試可指定 `CODE_SIGN_IDENTITY=-` 使用 ad hoc 簽章，但此方式無法跨版本保留權限授權

目前的建置結果尚未經過 Apple 公證，亦未製作正式安裝包

## 初次設定

首次開啟時，App 會顯示權限指引，請依序允許下列權限：

| 權限 | 用途 | 是否必要 |
| --- | --- | --- |
| 麥克風 | 錄製語音 | 必要 |
| 輔助使用 | 偵測輸入框並插入文字 | 必要 |
| 語音辨識 | 使用 macOS 系統辨識 | 僅限選用系統辨識時 |

之後可從側欄底部的權限指引重新開啟

若輔助使用開關已開啟，App 仍顯示未授權，通常是系統保留了舊版本的簽章授權，請至系統設定的隱私權與安全性，於輔助使用清單移除舊的 Hyday Talk，重新加入 `dist/Hyday Talk.app` 並開啟，再返回 App 按下重新檢查，詳細說明請參閱 [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

## 快捷鍵

| 操作 | 快捷鍵 |
| --- | --- |
| 開始或完成聽寫 | fn |
| 開始翻譯 | fn ＋ 左 Shift |
| 文字提問 | fn ＋ Space |
| 取消錄音或處理 | esc |

若按下 fn 會同時開啟表情符號或 macOS 聽寫，請至系統設定的鍵盤，將按下 🌐 鍵來設為不執行動作

## 語音辨識來源

| 來源 | 設定方式 | 資料處理 |
| --- | --- | --- |
| 系統辨識 | 允許語音辨識權限並選擇語言 | 由 Apple Speech 處理，部分語言可能使用 Apple 伺服器；可設定僅使用離線辨識 |
| 本機模型 | 於 App 內下載模型 | 以內建的 whisper.cpp 或 transcribe.cpp 在本機辨識，錄音不會上傳 |
| API | 設定服務網址、模型名稱與 API Key | 音訊傳送至指定的 OpenAI 相容服務 |

系統辨識單次錄音上限為 55 秒，其他來源為 180 秒

本機模型提供 Qwen3-ASR 0.6B（約 850 MB，推薦使用）、Qwen3-ASR 1.7B（約 1.69 GB）與 Whisper Large v3 Turbo（約 574 MB），Qwen3-ASR 對中文口語與中英夾雜較準確，下載完成後會驗證檔案大小與 SHA-256，模型存放於 `~/Library/Application Support/HydayTalk/Models/`，不納入版本控制或 App 安裝包

whisper.cpp 固定於 v1.9.2（commit `306c88f4d1286aec1bf96e544632897886af5501`），由 `scripts/build-whisper-runtime.sh` 取得並建置，以靜態連結方式內嵌於 App，使用者不需另行安裝

Qwen3-ASR 由 transcribe.cpp 執行，固定於 commit `f1dcd15858c4bbba87ca97862b4e448b2cf15b8f`，由 `scripts/build-transcribe-runtime.sh` 取得並建置，同樣以靜態連結內嵌於 App；模型檔取自 Hugging Face 的 handy-computer 轉檔，採 Apache 2.0 授權，個人詞典與 Hyday 詞彙會作為辨識詞彙提示

API 來源需支援 `POST /audio/transcriptions` 並回傳含 `text` 欄位的 JSON，遠端服務僅接受 HTTPS；本機服務可使用 HTTP 並免填 API Key

## 文字整理

| 方式 | 說明 |
| --- | --- |
| 基礎整理 | 轉換字形、將既有標點轉為全形並套用個人詞典，不補上新標點 |
| 本機 AI | 透過本機 Ollama 模型整理文字，逐字稿不會上傳 |
| API | 透過 OpenAI 相容的 `POST /chat/completions` 服務整理文字 |

聽寫風格分為自然、保留原話與正式，保留原話會略過 AI 整理，僅套用字形、既有標點與個人詞典

使用 AI 整理時，App 會：

- 補上標點與斷句，刪除口語贅字與冗長的轉折詞
- 依前後文修正同音或近音錯字，不改變說話者的原意
- 一般敘述保留為段落；連續列舉的事項改為編號列表，同一段輸出可同時包含段落與列表
- 保留所有事項、數字、英文與專有名詞的原寫法

回應檢查會拒絕未完成的結果、過長的分析文字，以及遺失原始數字或英文的內容，AI 整理失敗時保留原始辨識結果

繁體中文模式會將中文句子的半形標點轉為全形，並保留英文句子、數字、時間、版本、網址、電子郵件與程式碼

建議使用 7B 以上的本機模型以取得較佳的校稿與錯字修正效果

## 自動學習詞彙

插入聽寫文字後，App 會在使用者離開該輸入框、切換 App 或下次按下 fn 時讀回輸入框的內容並比對，找出使用者替換過的詞彙，再交由文字 AI 判斷是否為人名、品牌或術語等專有名稱，判定為專有名稱者會加入個人詞典並標示自動加入

- 僅處理聽寫，不處理翻譯與提問
- 刪除、標點修改、接續輸入與整段重寫不視為修正
- 一段插入文字中修正超過 3 處時視為重寫，不予學習
- 未啟用文字 AI 時不學習
- 僅在觀察期間偵測到使用者於該輸入框移動游標或輸入時才學習，避免學到他人造成的變動
- 學到的詞彙僅接受文字、數字、空白與少數連接符號，含換行、控制字元或其他符號者一律略過
- 新學到的詞彙標示為待確認，使用者於個人詞典按下確認後才會套用至辨識結果與文字 AI
- 使用者刪除的自動加入詞彙不會再次學習
- 無法讀取內容的 App 會直接略過

此功能可於一般設定關閉，預設為開啟

## 使用統計

使用統計另行儲存每日的字數、錄音秒數、筆數、使用時段、目標 App 與功能類型，不保存任何文字內容，清除或停用聽寫紀錄不會影響統計

節省時間的估算方式為口述字數除以使用者的打字速度，再扣除實際口述時間，打字速度預設為每分鐘 40 字，可於一般設定調整

## 隱私與資料儲存

- 設定、聽寫紀錄（最多 200 筆）與使用統計存放於 `~/Library/Application Support/HydayTalk/`，不使用雲端同步
- API Key 存放於 macOS 鑰匙圈，不寫入設定檔
- 系統辨識不寫入音訊檔；其他來源的暫存音訊於完成或取消後刪除，下次啟動時亦會清理殘留檔案
- 插入文字時透過剪貼簿送出貼上指令，並於 0.8 秒後還原原本的剪貼簿內容
- App 不讀取整份文件、瀏覽器頁面或剪貼簿歷史，並拒絕在密碼欄位開始錄音
- 使用 API 時，音訊、逐字稿、詞典與選取文字會依功能傳送至使用者指定的服務

## 驗證

```bash
swift test
bash scripts/build-app.sh
bash scripts/verify-signing.sh
python3 scripts/verify-app-flow.py
```

| 項目 | 內容 |
| --- | --- |
| `swift test` | 快捷鍵狀態、文字整理、詞典、修正偵測、使用統計、API 與本機模型等單元測試 |
| `verify-signing.sh` | 確認重新建置後的 App 仍符合原本的簽章身分，避免更新後失去系統權限 |
| `verify-app-flow.py` | 以固定測試資料驗證錄音、插入、自動複製、取消與紀錄保留流程 |

真實後端可使用下列指令驗證：

```bash
swiftc -parse-as-library Sources/TalkCore/*.swift scripts/verify-backends.swift -o .build/verify-backends
.build/verify-backends /opt/homebrew/bin/whisper-cli models/ggml-tiny.bin .build/verification/jfk.wav /usr/local/bin/ollama gemma3:4b
```

實際的麥克風權限、實體 fn 按鍵、各 App 的自動插入與個人 API 帳號，仍需於本機進行端對端測試

## 專案結構

| 路徑 | 內容 |
| --- | --- |
| `Sources/TalkCore` | 設定模型、文字整理、詞典、修正偵測、使用統計、API 與辨識介接 |
| `Sources/HydayTalk` | 錄音、權限、fn 快捷鍵、文字插入、介面與浮動錄音條 |
| `Tests/TalkCoreTests` | 核心邏輯的單元測試 |
| `Resources` | App 資訊、麥克風使用說明與 entitlements |
| `scripts` | 打包、圖示產生、簽章與後端驗證工具 |

介面樣式集中於 `Sources/HydayTalk/DesignTokens.swift`，設計規範請參閱 [DESIGN.md](DESIGN.md)，產品定位與限制請參閱 [PRODUCT.md](PRODUCT.md)，專案用語請參閱 [CONTEXT.md](CONTEXT.md)

## 參考資料

- [Apple Speech](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
- [OpenAI 語音辨識](https://developers.openai.com/api/docs/guides/speech-to-text)
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
- [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp)
- [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR)
