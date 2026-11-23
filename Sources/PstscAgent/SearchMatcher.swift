import Foundation

/// 搜索匹配。Windows 的开始菜单搜索只做子串匹配，中文用户想找「记事本」得切输入法打全字，
/// 而 Windows 上真正的习惯是打拼音首字母。这里补上：
///
/// - 子串匹配（原有行为）
/// - 拼音全拼（`jishiben` → 记事本）
/// - 拼音首字母（`jsb` → 记事本）
///
/// 首字母只对中日韩字符生效，英文名走原来的路径，不会出现 `notepad` 被拆成 `ntpd` 的怪结果。
enum SearchMatcher {
    /// 把一段文字转成小写拼音（不带声调），转不出来就返回原文。
    private static func pinyin(_ text: String) -> String? {
        let mutable = NSMutableString(string: text) as CFMutableString
        let ok = CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        guard ok else { return nil }
        let stripped = NSMutableString(string: mutable as String) as CFMutableString
        CFStringTransform(stripped, nil, kCFStringTransformStripCombiningMarks, false)
        return (stripped as String).lowercased()
    }

    /// 拼音首字母：按词取首字母。"记事本" → "jsb"，"Google Chrome" → "gc"。
    private static func initials(_ text: String) -> String {
        guard let full = pinyin(text) else { return "" }
        // 转出来的拼音用空格分词，取每个词的首字母。
        var result = ""
        var atWordStart = true
        for ch in full {
            if ch == " " {
                atWordStart = true
            } else if atWordStart {
                result.append(ch)
                atWordStart = false
            }
        }
        return result
    }

    /// 是否有中日韩字符。没有的话不必算拼音，省一次转换。
    private static func hasCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)      // 汉字
                || (0x3040...0x30FF).contains(scalar.value) // 假名
                || (0xAC00...0xD7AF).contains(scalar.value) // 谚文
        }
    }

    /// 命中程度，越小越靠前；nil 表示不匹配。
    /// 0 前缀、1 子串、2 拼音全拼、3 拼音首字母。
    static func score(name: String, query: String) -> Int? {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        if n.hasPrefix(q) { return 0 }
        if n.contains(q) { return 1 }

        // 只有查询里是纯 ASCII 时才尝试拼音（用户打的是拉丁字母）。
        let queryIsLatin = q.unicodeScalars.allSatisfy { $0.isASCII }
        guard queryIsLatin, hasCJK(name) else { return nil }

        if let full = pinyin(name), full.replacingOccurrences(of: " ", with: "").contains(q) { return 2 }
        if initials(name).hasPrefix(q) { return 3 }
        return nil
    }
}
