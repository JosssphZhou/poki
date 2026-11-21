import Foundation

enum MessageScrollTarget {
    case messages(Int)
    case screens(Int)

    var messageCount: Int? {
        if case .messages(let count) = self { return count }
        return nil
    }

    var isScreens: Bool {
        if case .screens = self { return true }
        return false
    }

    private static let digits = #"[0-9]+(?:,[0-9]{3})*"#
    private static let chineseNumber = "[0-9零〇一二两兩三四五六七八九十百千万萬亿億]+"
    private static let englishWord = #"one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million"#
    private static let englishNumber = "(?:\(englishWord))(?:[ -]+(?:\(englishWord)|and))*"
    private static let countBoundary = #"(?<![0-9+-])(?<![0-9][.,])"#
    private static let englishModifiers = #"(?:\s+[a-z]+(?:[-'][a-z]+)*)*?\s*"#
    private static let messageUnits: Set<String> = ["条", "條", "则", "則", "message", "messages", "msg", "msgs"]

    private static let quotedContentRegex = try! NSRegularExpression(
        pattern: #"『[^』]*』|「[^」]*」|“[^”]*”|"[^"]*"|‘[^’]*’"#,
        options: []
    )
    private static let chineseReportedSpeechRegex = try! NSRegularExpression(
        pattern: #"((?:发送|发|發|寄|回复|回覆|转发|轉發)[^。！？.!?;；\n]*?)(?:[，,]?\s*(?:说|說|写着|寫著|内容[是为：:]|告诉[^，,。！？\n]*[：:]))[^。！？.!?;；\n]*"#,
        options: []
    )
    private static let englishReportedSpeechRegex = try! NSRegularExpression(
        pattern: #"(\b(?:send|sending|text|texting|write|writing|reply|replying|forward|forwarding|dm|message)\b[^.!?;；\n]*?)(?:,?\s*(?:\bsaying\b|\bthat\s+says?\b|\btelling\b[^.!?;；\n]*?\bthat\b|:))[^.!?;；\n]*"#,
        options: [.caseInsensitive]
    )

    private static let nonScrollVerbRegex = try! NSRegularExpression(
        pattern: #"(?:发送|发|發|寄|写|寫|新建|添加|删|刪|转发|轉發|回复|回覆|买|買|订|訂|收藏|点赞|點讚|置顶|置頂|撤回|复制|複製|(?<!聊天)记(?!录)|(?<!聊天)記(?!錄)|\b(?:send|sending|text|texting|write|writing|compose|draft|reply|replying|forward|forwarding|delete|deleting|remove|removing|copy|copying|pin|pinning|star|starring|mute|mark)\b|\b(?:check\s+(?:my\s+)?latest|read\s+the\s+latest)\b)"#,
        options: [.caseInsensitive]
    )
    private static let explicitScrollVerbRegex = try! NSRegularExpression(
        pattern: #"(?:翻|滑|滚|滾|退到|退回|回退|倒退|往回|上移|下移|上拉|下拉|\b(?:scroll|scrolling|swipe|swiping)\b|\b(?:move|moving|go|going|step|jump|head|navigate)\s+(?:up|back|backward|backwards)\b)"#,
        options: [.caseInsensitive]
    )
    private static let scrollIntentRegex = try! NSRegularExpression(
        pattern: #"(?:翻|滑|滚|滾|退到|退回|回退|倒退|往回|往上|向上|往前|向前|上移|下移|上拉|下拉|回到|之前|以前|更早|消息前|訊息前|记录前|記錄前|\b(?:scroll|scrolling|swipe|swiping)\b|\b(?:move|moving|go|going|step|jump|head|navigate)\s+(?:up|back|backward|backwards)\b|\b(?:move|moving|go|going|scroll|scrolling|swipe|swiping)\b[^\n.!?;。！？]*?\b(?:up|back|earlier|older|previous|ago)\b|\b(?:older|earlier|previous)\s+(?:chat\s+)?(?:messages?|msgs?|pages?|screens?)\b|\b(?:messages?|msgs?|pages?|screens?)\s+(?:up|back|earlier|older|ago)\b|\bgo\s+to\b[^\n.!?;。！？]*?\b(?:earlier|older|previous|back|ago)\b)"#,
        options: [.caseInsensitive]
    )
    private static let chatLocationRegex = try! NSRegularExpression(
        pattern: #"群聊|私聊|聊天记录|聊天記錄"#,
        options: []
    )
    private static let sentenceSeparators = CharacterSet(charactersIn: "。！？.!?;；\n")
    private static let subClauseSeparators = CharacterSet(charactersIn: "。！？.!?;；\n，,、")

    private static let patterns = [
        "\(countBoundary)(\(digits)|\(chineseNumber))\\s*([条條则則页頁屏])",
        "\(countBoundary)(?<![a-z])(\(digits)|\(chineseNumber)|\(englishNumber))\(englishModifiers)(messages?|msgs?|pages?|screens?)\\b",
    ].map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    static func parse(_ request: String) -> MessageScrollTarget? {
        let folded = request.folding(options: .widthInsensitive, locale: nil).lowercased()
        let text = stripMessageBodies(folded)
        let range = NSRange(text.startIndex..., in: text)
        let matches = patterns.flatMap { $0.matches(in: text, range: range) }
            .sorted { $0.range.location < $1.range.location }
        for match in matches {
            guard let fullRange = Range(match.range, in: text),
                  let number = Range(match.range(at: 1), in: text),
                  let unit = Range(match.range(at: 2), in: text),
                  let count = integer(text[number]), count > 0 else { continue }
            guard hasScrollIntent(for: fullRange, in: text) else { continue }
            return messageUnits.contains(String(text[unit])) ? .messages(count) : .screens(count)
        }
        return nil
    }

    private static func stripMessageBodies(_ text: String) -> String {
        var cleaned = quotedContentRegex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " "
        )
        cleaned = chineseReportedSpeechRegex.stringByReplacingMatches(
            in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "$1"
        )
        cleaned = englishReportedSpeechRegex.stringByReplacingMatches(
            in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "$1"
        )
        return cleaned
    }

    private static func slice(around range: Range<String.Index>, in text: String, delimitedBy delimiters: CharacterSet) -> String {
        var start = range.lowerBound
        while start > text.startIndex {
            let prev = text.index(before: start)
            if text[prev].unicodeScalars.allSatisfy({ delimiters.contains($0) }) { break }
            start = prev
        }
        var end = range.upperBound
        while end < text.endIndex {
            if text[end].unicodeScalars.allSatisfy({ delimiters.contains($0) }) { break }
            end = text.index(after: end)
        }
        return String(text[start..<end])
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func hasScrollIntent(for matchRange: Range<String.Index>, in text: String) -> Bool {
        let subClause = slice(around: matchRange, in: text, delimitedBy: subClauseSeparators)
        if matches(nonScrollVerbRegex, in: subClause), !matches(explicitScrollVerbRegex, in: subClause) {
            return false
        }
        if matches(scrollIntentRegex, in: subClause) { return true }
        let sentence = slice(around: matchRange, in: text, delimitedBy: sentenceSeparators)
        return matches(chatLocationRegex, in: sentence) && !matches(nonScrollVerbRegex, in: sentence)
    }

    private static func integer(_ words: Substring) -> Int? {
        if let value = Int(words.replacingOccurrences(of: ",", with: "")) { return value }
        if let first = words.first, first.isASCII, first.isLetter {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .spellOut
            return formatter.number(from: String(words)).flatMap { Int($0.stringValue) }
        }
        let normalized = words.replacingOccurrences(of: "萬", with: "万").replacingOccurrences(of: "億", with: "亿")
        return chineseInteger(normalized[...], largePlaces: chineseLargePlaces[...])
    }

    private static let chineseDigits: [Character: Character] = [
        "零": "0", "〇": "0", "一": "1", "二": "2", "两": "2", "兩": "2",
        "三": "3", "四": "4", "五": "5", "六": "6", "七": "7", "八": "8", "九": "9",
    ]
    private static let chinesePlaces: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
    private static let chineseLargePlaces: [(Character, Int)] = [("亿", 100_000_000), ("万", 10_000)]

    private static func chineseInteger(_ words: Substring, largePlaces: ArraySlice<(Character, Int)>) -> Int? {
        guard let (symbol, scale) = largePlaces.first else { return chineseSection(words) }
        let smallerPlaces = largePlaces.dropFirst()
        guard let divider = words.firstIndex(of: symbol) else { return chineseInteger(words, largePlaces: smallerPlaces) }
        let remainder = words[words.index(after: divider)...]
        guard let leading = chineseInteger(words[..<divider], largePlaces: smallerPlaces), leading > 0,
              let trailing = remainder.isEmpty ? 0 : chineseInteger(remainder, largePlaces: smallerPlaces),
              trailing < scale else { return nil }
        let (scaled, overflow) = leading.multipliedReportingOverflow(by: scale)
        let (sum, sumOverflow) = scaled.addingReportingOverflow(trailing)
        return overflow || sumOverflow ? nil : sum
    }

    // Consecutive digits are read in order. A place marker multiplies the digits just before it.
    private static func chineseSection(_ words: Substring) -> Int? {
        guard !words.isEmpty else { return nil }
        var digits = ""
        var total = 0
        var previousPlace = 10_000
        for character in words {
            if let digit = chineseDigits[character] {
                digits.append(digit)
            } else if character.isASCII, character.isNumber {
                digits.append(character)
            } else {
                guard let place = chinesePlaces[character], place < previousPlace else { return nil }
                let coefficient = digits.isEmpty && place == 10 ? 1 : Int(digits)
                guard let coefficient, coefficient > 0 else { return nil }
                let (scaled, overflow) = coefficient.multipliedReportingOverflow(by: place)
                let (sum, sumOverflow) = total.addingReportingOverflow(scaled)
                guard !overflow, !sumOverflow else { return nil }
                total = sum
                previousPlace = place
                digits = ""
            }
        }
        guard let units = digits.isEmpty ? 0 : Int(digits) else { return nil }
        let (value, overflow) = total.addingReportingOverflow(units)
        return overflow ? nil : value
    }
}
