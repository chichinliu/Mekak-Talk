---
name: Mekak Talk
description: 原生 macOS 語音輸入工作區，淺灰工作區、柔和卡片與細字重數據
colors:
  workspace: "#F3F5F9"
  sidebar: "#F3F5F9"
  card: "#FCFCFC"
  surface: "#FFFFFF"
  subtle-surface: "#ECEBEC"
  canvas: "#FEFEFE"
  ink: "#111C34"
  muted: "#6A6F78"
  faint: "#A3A8B1"
  border: "#E3E5E9"
  accent: "#1E4B99"
  accent-ink: "#163A7A"
  accent-surface: "#E8EEF8"
  accent-border: "#C5D3EC"
  action: "#2E6BF0"
  action-ink: "#2453C2"
  action-surface: "#EEF3FF"
  action-border: "#D9E4FD"
  ai: "#7A5AF8"
  ai-surface: "#F3F0FF"
  success: "#1F9D62"
  success-ink: "#157048"
  success-surface: "#E8F7EF"
  success-border: "#CDEBDB"
  warning: "#E5A23A"
  warning-ink: "#8A5A12"
  warning-surface: "#FFF8EC"
  warning-border: "#F6E3BF"
  danger: "#CF302A"
  danger-surface: "#FFEFEB"
typography:
  page-title:
    fontFamily: "system-ui, PingFang TC, sans-serif"
    fontSize: "26pt"
    fontWeight: 600
  section:
    fontFamily: "system-ui, PingFang TC, sans-serif"
    fontSize: "16pt"
    fontWeight: 500
  body:
    fontFamily: "system-ui, PingFang TC, sans-serif"
    fontSize: "14pt"
    fontWeight: 400
  caption:
    fontFamily: "system-ui, PingFang TC, sans-serif"
    fontSize: "13pt"
    fontWeight: 400
  metric:
    fontFamily: "system-ui, PingFang TC, sans-serif"
    fontSize: "32pt"
    fontWeight: 400
  keycap:
    fontFamily: "ui-monospace, monospace"
    fontSize: "11pt"
    fontWeight: 500
rounded:
  keycap: "6pt"
  control: "8pt"
  segmented: "10pt"
  inner: "12pt"
  surface: "20pt"
spacing:
  tight: "4pt"
  small: "8pt"
  control: "12pt"
  group: "16pt"
  surface: "20pt"
  section: "28pt"
components:
  button-primary:
    backgroundColor: "{colors.action}"
    textColor: "{colors.surface}"
    rounded: "{rounded.control}"
    padding: "8pt 12pt"
  button-accent:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.surface}"
    rounded: "{rounded.control}"
    padding: "8pt 16pt"
  button-secondary:
    backgroundColor: "{colors.subtle-surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "8pt 12pt"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "8pt 12pt"
  card:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    rounded: "{rounded.surface}"
    padding: "{spacing.surface}"
  navigation-selected:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "9pt"
    padding: "10pt 12pt"
  status-ready:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.success-ink}"
    padding: "5pt 10pt"
---

# Design System: Mekak Talk

## Overview

**Creative North Star: 安靜的工作區，重點用細節說話**

整個視窗是一片淺灰，卡片只比背景亮一點，層次靠很淡的陰影與內側白色亮邊，不靠框線。白色留給最需要注意的東西，例如整理結果、比較膠囊與圖表標籤

數字用細字重的大字，標題用中等字重，層次靠字級與灰階拉開，不靠粗體。顏色只用在有意義的數字與圖形，不做裝飾

來源檔案為 Sources/MekakTalk 下的 DesignTokens.swift、AlignComponents.swift、Views.swift、HomeComponents.swift、InsightsViews.swift、SettingsViews.swift、PermissionGuide.swift、VoicePanel.swift；產品能力以 PRODUCT.md 為準

**Key Characteristics:**
- 原生 SwiftUI 與 macOS 控制行為
- 淺灰工作區、柔和卡片、白色只用在重點
- 細字重的大數字與單行頁面標題
- 斜線紋表示過去或估算，實色表示現在
- 不使用黑色主色，不顯示焦點粗框

## Colors

數值以 frontmatter 為準，Swift 的 Palette 為實作來源

### Neutral
- **工作區與側欄（workspace、sidebar）**：整個視窗的底色，側欄與內容同色，不加分隔線
- **卡片（card）**：所有獨立區塊的底色
- **表面白（surface）**：卡片內要凸顯的元素，例如整理結果、側欄選中項目、膠囊、鍵帽
- **淡灰層（subtle-surface）**：分段選擇器底板、次要按鈕、圖示圓形底
- **輔助灰與淡灰字（muted、faint）**：說明、標籤、刻度
- **細線（border）**：列與列之間的分隔線

### Semantic
- **品牌藍（accent）**：品牌標記、開始聽寫按鈕、錄音音量、使用時段熱度
- **操作藍（action）**：選取、主要按鈕、開關、圖表的目前值
- **紫色（ai）**：文字 AI 相關，例如提問比例
- **綠色（success）**：就緒、節省時間、增加的比較
- **黃色（warning）**：待設定
- **紅色（danger）**：減少的比較、處理失敗、破壞性操作

**The 一色一義 Rule.** 每個顏色只代表一件事；不加裝飾用的色點、色條或彩色方塊

## Typography

**Font:** macOS 系統字型，繁體中文回退至 PingFang TC；快捷鍵、API 端點、模型與路徑使用等寬字型；數字使用等寬數字

### Hierarchy
- **Page title**：頁面名稱，單行
- **Section**：區塊標題，medium，下方可接一行灰色說明
- **Body**：內文、設定列標題、按鈕
- **Caption**：說明、標籤、比較、圖表刻度，資訊文字下限 13 pt
- **Metric**：數據列與統計卡的大數字，regular 或 light，字距收緊，單位用 caption 灰字
- **Keycap**：鍵帽 11 pt 等寬 medium

**The 少用粗體 Rule.** 層次靠字級與灰階；數字、列表值與區塊標題都不使用 semibold 以上

**The 單行標題 Rule.** 頁面與區塊標題維持一行，不縮字、不裁切、不加省略號

## Layout

主視窗為固定側欄加可捲動內容，內容填滿可用寬度，頁面左右留白 28 pt

- **總覽**：最上方數據列；下方左欄為錄音區、輸出示範、目前設定與快捷鍵，右欄為 300 pt 寬的使用統計卡，高度跟左欄對齊；可用寬度不足 760 pt 時統計卡移到最下方
- **洞察**：數據列，近 12 週與重點卡，口述速度趨勢，使用時段與功能使用比例，常用 App 與每筆口述長度，最下方三張並排的個人紀錄、連續使用、個人辭典
- **設定頁**：內容最寬 760 pt；區塊標題放在卡片外上方，卡片內為設定列，左邊標題與灰色說明，右邊控制項，列之間用細線分隔；區塊間距 28 pt，明顯大於區塊內間距

權限指引為原生 sheet（860 × 680 pt），底色與主視窗相同。浮動錄音條置於滑鼠所在螢幕可見區域底部 24 pt，收合 300 × 52 pt，展開 300 × 200 pt

## Elevation & Depth

卡片不用框線，以兩層很淡的陰影加一圈內側白色亮邊浮在工作區上。按鈕與輸入框不加陰影。白色膠囊與側欄選中項目可用極淡的單層陰影

### Shadow Vocabulary
- **卡片接觸陰影**：黑色 4%，radius 1 pt，y 1 pt
- **卡片環境陰影**：黑色 4%，radius 8 pt，y 4 pt
- **卡片亮邊**：白色 80%，1 pt，內側
- **膠囊陰影**：黑色 6% 至 8%，radius 1.5 pt，y 1 pt

浮動錄音條的陰影交由 NSPanel 處理

## Shapes

卡片圓角 20 pt；卡片內白色區塊 12 至 14 pt，與外層同心；控制項 8 pt；分段底板 10 pt；鍵帽 6 pt；狀態與比較使用膠囊。圖示放在圓形淡灰底上

## Components

### Buttons
- **Primary**：藍底白字，上緣淡淡亮光，hover 變深
- **Accent**：藍底白字，只用在開始聽寫，文字一般字重
- **Secondary**：淡灰底，無框線，hover 稍深
- **Ghost**：透明底，hover 淡灰
- **Destructive**：紅字，保留細框
- 全部按鈕無陰影、無焦點框，滑鼠移上顯示手指游標；按下縮放 0.96，尊重減少動態效果

### Data strip
同一張卡片內多欄，細線分隔；每欄為灰色小標、細字重大數字、下方一行說明或白色比較膠囊（綠色上三角表示增加，紅色下三角表示減少）

### Charts
- 長條：過去為淡藍斜線紋，目前為實色藍，上方放白色數值膠囊
- 折線：藍色線與點，下方淡藍漸層，格線為淡灰虛線，最新一點加白色標籤
- 熱度格：顏色越深代表越多，附較少與較多圖例
- 點陣：每點一筆，平均值用金色虛線標示
- 每張圖都提供無障礙的數值說明

### Highlight card
藍色漸層到金黃色的重點卡，白字，顯示從資料找出的一句使用習慣

### Settings row
左邊標題與灰色說明，右邊開關、下拉選單、鍵帽或按鈕；多列放同一張卡片，用細線分隔

### Status badge
白色膠囊，彩色字與帶光暈的小圓點；就緒為綠色，待設定為黃色

### Navigation
側欄與工作區同色；選中項目為白色膠囊加極淡陰影，圖示為品牌藍；圖示一律細線條

### Floating voice capsule
淺灰膠囊，背景 #F4F5F7，寬 256；錄音時依序為圖示、填滿中間的捲動波形、等寬計時、停止鍵與關閉，新的音量從右側進入，越舊越淡；不成為 key 或 main window，保留目標 App 焦點；插入或自動複製後關閉

## Do's and Don'ts

### Do:
- **Do** 使用共用 token 與元件，資訊文字至少 13 pt
- **Do** 用正式、簡短的台灣繁體中文，保留使用者既有的文案
- **Do** 白色只用在重點，顏色只用在有意義的數字與圖形
- **Do** 數字用細字重大字，比較用白色膠囊
- **Do** 統計、版本、模型與紀錄都從實際資料取得

### Don't:
- **Don't** 使用黑色主色或深色大面積區塊
- **Don't** 加焦點粗框、按鈕陰影或輸入框陰影
- **Don't** 用小卡片拆分數據，或加裝飾色點與色條
- **Don't** 在使用者可見的文字中提及其他產品或參考來源
- **Don't** 轉成 WKWebView 或引入第二套樣式來源
- **Don't** 把示範內容、合成紀錄或估算數字當成產品事實
