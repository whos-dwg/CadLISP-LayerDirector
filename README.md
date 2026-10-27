# LDON / LDOFF / LDM 依命令自動分層

![LDON / LDOFF / LDM](assets/banner.svg)

[工具儲存庫](https://github.com/whos-dwg/CadLISP-LayerDirector) · [全部工具索引](https://github.com/whos-dwg/CadLISP-Index)

執行文字、引線與尺寸命令時暫時切換對應圖層，結束後還原；外部參考依名稱分層。

| 項目 | 內容 |
| --- | --- |
| 指令 | `LDON`、`LDOFF`、`LDM` |
| 檔案 | [LayerDirector.lsp](lsp/LayerDirector.lsp) |
| 分類 | 配置與圖層 |
| 狀態 | 來源快照，實機回歸待完成 |
| 授權 | [MIT](LICENSE)，Copyright (c) 2026 whos-dwg |

[安裝](#安裝) · [操作](#操作) · [相依與設定](#相依與設定) · [已知問題](docs/KNOWN_ISSUES.md) · [驗證紀錄](docs/VALIDATION.md)

## 安裝

以 Windows 桌面版 AutoCAD 為目標。原碼使用的 Visual LISP／ActiveX、DCL 或原生命令，需在目標 AutoCAD 版本分別確認；尚未做整包年份、LT、Mac 或其他 CAD 的相容性認證。ActiveX 的平台限制見 [Autodesk](https://help.autodesk.com/cloudhelp/2026/ENU/AutoCAD-AutoLISP/files/GUID-A0459510-CE7A-4206-9EAA-E25AAB569B20.htm)。

1. 下載並解壓縮本工具到固定位置，先開啟測試圖面。
2. 依公司環境把 `lsp` 資料夾加入需要的支援搜尋路徑與受信任位置。
3. 輸入 `APPLOAD`，載入 `LayerDirector.lsp`；關閉視窗後輸入 `LDM`。

也可使用完整路徑單獨載入；下列路徑需依實際位置修改：

```lisp
(load "C:/CAD/CadLISP-LayerDirector/lsp/LayerDirector.lsp")
```

完成驗證後，可將這支 LISP 加入 APPLOAD 的 Startup Suite。請維持既定的 SECURELOAD 政策，使用受信任位置處理載入限制。[SECURELOAD 說明](https://help.autodesk.com/cloudhelp/2026/ENU/AutoCAD-Core/files/GUID-541566C6-2738-49DD-87C3-C1490E924A02.htm)。

## 操作

1. 輸入 `LDM`，選 LA-、RC-、FC-、SO-、EM-、E-、D- 或 A-。
2. 建立文字、引線或尺寸，檢查 <前綴>text 與 <前綴>dim 圖層。
3. 使用 `LDOFF` 停止監聽，`LDON` 恢復。

## 相依與設定

載入即建立命令監聽；預設前綴 LA-。DCL 對話框由程式在暫存資料夾產生。

圖面影響：建立圖層、設定註解圖層與新附加 XREF 的圖層。

## 行為與限制

缺少圖層才建立預設性質，既有圖層沿用原設定。命令期間暫改 ByLayer 與相關註解圖層變數。LDM 對話框關閉後會重新啟用，即使按 Cancel 也一樣。

## 操作示範

![依命令自動分層操作示範](assets/demos/ldm.gif)

這是既有操作錄影，未與本快照逐段比對；本次不是以錄影作為實機回歸證據。媒體範圍見 [媒體說明](assets/NOTICE.md)。

## 來源與授權

本工具依維護者確認為自行從零撰寫，或以 AI 協作從零開發。程式與本次文件採 [MIT 授權](LICENSE)，允許使用、修改與再散布，須保留授權及著作權聲明。詳細來源紀錄見 [provenance.json](metadata/provenance.json)。

## 回報與維護

回報時附 AutoCAD 完整版本、命令列錯誤與去識別的重現範例。修改前請閱讀 [CONTRIBUTING](CONTRIBUTING.md)；發行步驟見 [PUBLISHING](docs/PUBLISHING.md)。本工具可獨立維護、下載及發布，不依賴其他 CadLISP 工具儲存庫。
