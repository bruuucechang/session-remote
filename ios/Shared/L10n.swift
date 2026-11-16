import Foundation

/// 執行時才知道的字（分區標題、後端回的訊息）查 String Catalog；查不到照原文
func L(_ s: String) -> String { Bundle.main.localizedString(forKey: s, value: s, table: nil) }

/// 後端回給手機顯示的中文（錯誤 detail、「已中斷」、計畫核准的說明）在 app 這端翻：後端不用知道手機的語言，
/// 舊版後端也照樣翻得到。整句查不到就拆成「前綴：後面」查前綴（例如「不收這種檔案：.exe」）。
func serverText(_ s: String) -> String { serverText(s, lookup: L) }

func serverText(_ s: String, lookup: (String) -> String) -> String {
    let t = lookup(s)
    if t != s { return t }
    guard let r = s.range(of: "：") else { return s }  // l10n:skip 拆後端訊息的前綴
    let head = String(s[..<r.upperBound])
    if lookup(head) != head { return lookup(head) + s[r.upperBound...] }
    // routers 會把例外包成「iTerm2：<內層訊息>」：前綴是名稱、不用翻，翻後面那段
    let rest = String(s[r.upperBound...])
    let inner = serverText(rest, lookup: lookup)
    return inner == rest ? s : s[..<r.lowerBound] + ": " + inner
}

/// app 實際用的介面語言（英文或繁中）。「3 小時前」這類系統格式要跟著它，不能跟手機地區走（地區可能是第三種語言）
let appLocale = Locale(identifier: Bundle.main.preferredLocalizations.first == "en" ? "en" : "zh_Hant_TW")
