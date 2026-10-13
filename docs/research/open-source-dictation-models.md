# 開源熱鍵聽寫 App 使用的語音模型

查證日期：2026-10-12。先以 Jev 找官方來源，再讀取官方 README、授權、模型登錄、推論程式與模型卡。下表描述當日官方 `main` 原始碼；已發布安裝包可能落後於 `main`。沒有在本機執行這些 App，也沒有用使用者錄音比較辨識品質。

多語 Whisper 是這類 App 常見的語音辨識模型；部分專案也提供 Parakeet、SenseVoice 等模型。台灣國語與中英混說值得優先對照 **Breeze ASR 25**，Handy 已正式收進模型目錄。Parakeet v2/v3 並不是中文選項。

| 開源 App／App 授權 | 主要語音模型與推論引擎 | 本機／雲端 | 中文與繁中適用性 |
| --- | --- | --- | --- |
| [Handy](https://github.com/cjpais/Handy/blob/7b2a28a30aa24174292ddd7f4e92e12e6e3bd501/README.md)／[MIT](https://github.com/cjpais/Handy/blob/7b2a28a30aa24174292ddd7f4e92e12e6e3bd501/LICENSE) | 現行 [GGUF 模型目錄](https://github.com/cjpais/Handy/blob/7b2a28a30aa24174292ddd7f4e92e12e6e3bd501/src-tauri/src/catalog/catalog.json)：Whisper、Breeze ASR 25、SenseVoice、Parakeet 等；[transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) 推論，macOS 啟用 Metal。舊 ONNX 模型路徑仍使用 transcribe-rs／ONNX。 | 語音辨識在本機。文字後處理另行設定。 | Breeze 官方針對繁中及台灣國語；多語 Whisper、SenseVoice 可辨識中文。Parakeet v2/v3 無中文。 |
| [VoiceInk](https://github.com/Beingpax/VoiceInk/blob/c09cc1f677f40f2ee665843a61f07670210f012e/README.md)／[GPL v3](https://github.com/Beingpax/VoiceInk/blob/c09cc1f677f40f2ee665843a61f07670210f012e/LICENSE) | [模型登錄](https://github.com/Beingpax/VoiceInk/blob/c09cc1f677f40f2ee665843a61f07670210f012e/VoiceInk/Features/ModelLibrary/Models/TranscriptionModelRegistry.swift)：Whisper tiny/base/large-v2/large-v3/turbo，含部分 `.en` 版 → whisper.cpp；Parakeet → FluidAudio；SenseVoice Small、Cohere Transcribe → transcribe.cpp；另有 Apple Speech 與雲端來源。 | 可選本機或雲端。 | 可選多語 Whisper、SenseVoice；`.en` 和 Parakeet v2/v3 不適合中文。支援中文不等於保證台灣用詞與繁體字，仍須驗證輸出。 |
| [OpenWhispr](https://github.com/OpenWhispr/openwhispr/blob/5f9a88b0481a066c147bfd2c38ea1d9acae502ee/README.md)／[MIT](https://github.com/OpenWhispr/openwhispr/blob/5f9a88b0481a066c147bfd2c38ea1d9acae502ee/LICENSE) | [模型登錄](https://github.com/OpenWhispr/openwhispr/blob/5f9a88b0481a066c147bfd2c38ea1d9acae502ee/src/models/modelRegistryData.json)：Whisper tiny/base/small/medium/large/turbo → whisper.cpp；Parakeet、Orukeet、Nemotron、Cohere Transcribe → sherpa-onnx。 | 可選本機、服務商雲端或自訂端點。 | 多語 Whisper 及登錄中含 `zh` 的 Cohere 是中文選項；Parakeet v3 清單沒有中文。未證實上述模型可固定輸出台灣繁中。 |
| [open-wispr](https://github.com/human37/open-wispr/blob/f16227ce836148f7310affa464d27f8b74eaed8f/README.md)／[MIT](https://github.com/human37/open-wispr/blob/f16227ce836148f7310affa464d27f8b74eaed8f/LICENSE) | Whisper → whisper.cpp，Apple Silicon 使用 Metal。預設 **base.en**；可改為多語 base、large-v3-turbo、large-v3 與量化版。 | 本機。 | 預設英文模型不能直接當中文方案；須切多語版並設定 `language: zh`。 |

Whispering 常見於舊比較文章，但目前 [官方 main README](https://github.com/EpicenterHQ/epicenter/blob/6100613ea3fa7c7362527f2ddfadf376aee4b457/apps/whispering/README.md) 已描述為獨立錄音筆記 App，使用自訂 OpenAI 相容辨識端點，並明言此版本沒有跨 App 聽寫；目前是開發里程碑。它仍有 [AGPL v3 授權](https://github.com/EpicenterHQ/epicenter/blob/6100613ea3fa7c7362527f2ddfadf376aee4b457/apps/whispering/LICENSE)，但不列入上面的現況同類 App 比較，也不把舊版模型清單套到新版。

## 台灣繁中最相關的模型與格式限制

**Breeze ASR 25** 的官方識別字是 `MediaTek-Research/Breeze-ASR-25`，由 Whisper-large-v2 微調。官方明列繁體中文情境、台灣國語、中英句內及句外混說，模型卡目前標示 Apache-2.0。[MediaTek 官方模型卡](https://huggingface.co/MediaTek-Research/Breeze-ASR-25)

Handy 的現行條目是 `handy-computer/Breeze-ASR-25-gguf`，模型 revision 為 `1e5e8d7295110e1e14e305e9cf7411d82711beaa`；預設量化檔 `Breeze-ASR-25-Q5_K_M.gguf`，**1,160,366,080 bytes，約 1.16 GB**。目錄明列上游為 Breeze ASR 25、語言 `zh`／`en`。[Handy 模型目錄](https://github.com/cjpais/Handy/blob/7b2a28a30aa24174292ddd7f4e92e12e6e3bd501/src-tauri/src/catalog/catalog.json#L2108)；[Handy 轉檔模型卡及 transcribe-cli 使用方式](https://huggingface.co/handy-computer/Breeze-ASR-25-gguf)

這個 **GGUF 供 transcribe.cpp 使用，不能直接交給目前 Hyday Talk 的 whisper-cli GGML 路徑**。whisper.cpp 載入器要求 GGML 檔頭；其官方轉換程式可將 Hugging Face 的 Whisper 微調模型轉成 GGML。因此 Breeze 的模型架構可以沿用 Whisper 家族，但必須取得或自行產生正確的 GGML `.bin`。[whisper.cpp 載入器](https://github.com/ggml-org/whisper.cpp/blob/master/src/whisper.cpp#L1497)；[官方微調模型轉換程式](https://github.com/ggml-org/whisper.cpp/blob/master/models/convert-h5-to-ggml.py)

Handy 還保留 `breeze-asr-q5_k.bin`、`size_mb: 1030` 的舊條目，但程式說明舊 URL 型模型在未下載時由 UI 隱藏，已下載者繼續可用。它不是現在應優先描述的下載路徑。[舊條目](https://github.com/cjpais/Handy/blob/7b2a28a30aa24174292ddd7f4e92e12e6e3bd501/src-tauri/src/managers/model.rs#L710)；[新舊目錄處理](https://github.com/cjpais/Handy/blob/7b2a28a30aa24174292ddd7f4e92e12e6e3bd501/src-tauri/src/managers/model.rs#L1204)

有轉檔發布者提供約 2.9 GB 的 Breeze GGML 並示範 whisper.cpp 命令；這是第三方轉檔，並非 MediaTek 直接發布的 GGML。這份調查未下載或實跑該檔，不能承諾特定檔案、量化格式與本機 whisper-cli 版本已通過相容驗證。[轉檔發布者模型卡](https://huggingface.co/danielkao0421/Breeze-ASR-25-ggml)

## 不應混在一起的三層

- **語音辨識模型**：Whisper、Breeze、SenseVoice、Parakeet；決定音訊辨識能力與語言範圍。Whisper 多語版有 `zh`，`.en` 是英文專用；Parakeet v2 是英文，v3 的 25 種語言清單沒有中文。[Whisper 模型表](https://github.com/openai/whisper#available-models-and-languages)；[Whisper 語言表](https://github.com/openai/whisper/blob/main/whisper/tokenizer.py#L12)；[Parakeet v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)；[Parakeet v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
- **推論引擎**：whisper.cpp、transcribe.cpp、FluidAudio、sherpa-onnx；負責執行模型，不是另一個辨識模型。不同引擎的檔案格式及硬體加速方式不同。Handy 最新 macOS 依賴明列 transcribe-cpp 的 Metal 功能。[Handy Cargo 設定](https://github.com/cjpais/Handy/blob/7b2a28a30aa24174292ddd7f4e92e12e6e3bd501/src-tauri/Cargo.toml#L151)
- **文字整理模型**：逐字稿之後再接 LLM，做去贅詞、潤稿或翻譯。VoiceInk 可另外選 Ollama、CLI 或 API；OpenWhispr 可用 llama.cpp 執行本機 LLM。這些不能當成 App 的 ASR 模型。[VoiceInk 整理流程](https://github.com/Beingpax/VoiceInk/blob/c09cc1f677f40f2ee665843a61f07670210f012e/VoiceInk/Features/Enhancement/Workflows/AIEnhancementService.swift)；[OpenWhispr 技術說明](https://github.com/OpenWhispr/openwhispr/blob/5f9a88b0481a066c147bfd2c38ea1d9acae502ee/README.md#acknowledgments)

SenseVoice Small 官方支援國語、粵語、英文、日文、韓文，是另一個中文候選；它的模型權重使用另列的 FunASR 模型授權，不應因 App 使用 MIT 就推定模型也是 MIT。這份調查不把它列為「台灣繁中已驗證」模型。[SenseVoice 官方模型卡](https://huggingface.co/FunAudioLLM/SenseVoiceSmall)

## Hyday Talk 的實際選擇

先保留現有 whisper.cpp 接口，以多語 `small` 或 `large-v3-turbo` 建立基準；把 **Breeze ASR 25 的正確 GGML 轉檔**列為台灣國語／中英混說的優先對照候選。這是根據語言支援、官方訓練定位及現有架構的選擇，不代表已證實它對使用者的錄音最準。[Whisper 官方模型說明](https://github.com/openai/whisper#available-models-and-languages)；[Breeze 官方模型卡](https://huggingface.co/MediaTek-Research/Breeze-ASR-25)

tiny 可繼續做工程試跑，但選定日常預設前，應用相同的台灣口語、中英混說、個人專名錄音，檢查漏字／錯字、繁簡字、台灣用詞、空音訊誤輸出及停止錄音後等待時間。App 模型選單裡的 accuracy／speed 分數不是我們自己的測試結果，不拿來做品質排名。繁體轉換、詞典替換和選用 LLM 整理繼續分開處理。

如果日後想直接使用 Handy 的 GGUF 生態，再評估新增 transcribe.cpp 後端；這涉及另一套模型載入與 CLI 契約，不是只換 `.bin` 路徑。這次研究沒有修改 App 程式或模型設定。
