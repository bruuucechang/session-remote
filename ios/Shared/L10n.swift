import Foundation

/// 執行時才知道的字（分區標題、後端回的訊息）查 String Catalog；查不到照原文
func L(_ s: String) -> String { Bundle.main.localizedString(forKey: s, value: s, table: nil) }

/// 後端回給手機顯示的中文（錯誤 detail、「已中斷」、計畫核准的說明）在 app 這端翻：後端不用知道手機的語言，
/// 舊版後端也照樣翻得到。整句查不到就拆成「前綴：後面」查前綴（例如「不收這種檔案：.exe」）。
func serverText(_ s: String) -> String {
    let t = L(s)
    if t != s { return t }
    if let r = s.range(of: "："), case let head = String(s[..<r.upperBound]), L(head) != head {  // l10n:skip 拆後端訊息的前綴
        return L(head) + s[r.upperBound...]
    }
    return s
}

/// app 實際用的介面語言（英文或繁中）。「3 小時前」這類系統格式要跟著它，不能跟手機地區走（地區可能是第三種語言）
let appLocale = Locale(identifier: Bundle.main.preferredLocalizations.first == "en" ? "en" : "zh_Hant_TW")
