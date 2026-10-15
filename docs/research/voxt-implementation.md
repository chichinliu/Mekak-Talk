# Voxt 的語音辨識與文字插入實作

查閱日期：2026-10-12；來源版本：`baa6f316a6648cc0ef90c70d724acd10085eedaa`，以原始碼為準，未執行 Voxt。

## 模型與辨識流程

Voxt 的本機辨識採用 MLX／MLXAudioSTT，預設模型為 `mlx-community/Qwen3-ASR-0.6B-4bit`，模型目錄也包含 Qwen3 1.7B、Whisper Large v3 Turbo／Large v3／Small、SenseVoice、Parakeet 等，依模型能力選用不同 loader、語言路由與即時預覽方式，並非把所有模型交給同一個 whisper-cli。

Qwen3 的語言列表包含 `zh`；Parakeet v3 在該目錄標為歐洲 25 語種，其語言列表不含中文；Voxt 的舊 tiny／base 設定會遷移至 Whisper Small。

來源：[模型目錄與能力](https://github.com/hehehai/voxt/blob/baa6f316a6648cc0ef90c70d724acd10085eedaa/Voxt/Transcription/MLXModelSupport.swift#L202)、[不同模型的 loader](https://github.com/hehehai/voxt/blob/baa6f316a6648cc0ef90c70d724acd10085eedaa/Voxt/Transcription/MLXSTTModelLoader.swift)。

## 文字插入流程

Voxt 記住錄音開始時的目標 PID／bundle ID；若完成時自己的視窗位於前景，會先啟用原 App，等待約 40 ms 後再貼上；若已切換到另一個外部 App，就不主動搶回焦點。

輸入走剪貼簿加 Cmd+V，使用 HID event source 與 annotated session event tap；它沒有在主要輸出流程直接設定 AXSelectedText。剪貼簿在 0.8 秒後還原，期間使用者或其他工具變更剪貼簿時不還原；另外有 output generation 與 transaction 檢查，避免取消或新錄音後仍送出舊結果。

Voxt 的焦點解析有 App、視窗、系統層級與子元素的備援，實作也包含可編輯性檢查，但 Mekak Talk 保留更嚴格的原輸入框、游標與選取文字檢查，避免結果插入使用者新切換的位置。

來源：[文字輸出](https://github.com/hehehai/voxt/blob/baa6f316a6648cc0ef90c70d724acd10085eedaa/Voxt/App/TextOutputDelivery.swift)、[焦點解析](https://github.com/hehehai/voxt/blob/baa6f316a6648cc0ef90c70d724acd10085eedaa/Voxt/App/TextInputIO.swift)。

## 本次在 Mekak Talk 套用的調整

- 統一使用 Cmd+V，使終端機／網頁編輯器接收正常貼上事件，並保留焦點、游標、密碼欄位與取消檢查。
- 加入同 PID 的系統焦點備援與 AX 參照保存，僅在開始錄音時讀取選取文字。
- 目前既有 whisper.cpp 路徑改用多語 `large-v3-turbo-q5_0`，沒有把 MLX 權重誤當成 GGML。
- 拒絕只有框線／分隔線的辨識輸出。

MLX + Qwen3 可作為後續本機引擎方向，需要另外整合模型下載、MLX runtime、音訊串流與生命週期；本次尚未實作該引擎。

## 本機辨識驗證

模型下載自 [whisper.cpp 文件指定的 Hugging Face 倉庫](https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md)，`ggml-large-v3-turbo-q5_0.bin` 大小為 574,041,195 bytes，SHA-256 為 `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`，已驗證。

同一份 16 kHz 單聲道合成中文音訊，tiny 輸出「這是一段與應變式測試」，large-v3-turbo 輸出「这是一段语音辨识测试」，再由 App 轉成正體中文；單次完整 CLI 呼叫分別約 0.34 秒與 1.51 秒（Apple M4 Pro），此例只驗證改善與相容性，不代表真實語音的準確率或延遲基準。

插入驗證：使用者在更新後的 App 實際以 fn 開始／完成錄音，回覆 TempoTerm 已成功插入；電腦操作工具不支援 fn，因此此項為使用者實測確認，不列為自動測試。
