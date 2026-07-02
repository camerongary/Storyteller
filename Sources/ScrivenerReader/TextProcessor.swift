import Foundation
import NaturalLanguage

struct WordToken {
    let text: String
    let range: NSRange
}

struct Sentence {
    let range: NSRange
    let wordRanges: [NSRange]
}

class TextProcessor {
    let fullText: String
    let chapters: [(title: String, charOffset: Int)]
    private(set) var sentences: [Sentence] = []
    private(set) var wordTokens: [WordToken] = []
    private(set) var repeatedWordLocations: Set<Int> = []
    /// Word count of each chapter, parallel to `chapters`.
    private(set) var chapterWordCounts: [Int] = []

    /// Common function words excluded from repeated-word highlighting.
    private let stopWords: Set<String> = [
        // Articles, conjunctions, prepositions
        "the","a","an","and","or","but","nor","yet","in","on","at","to","for",
        "of","with","by","from","as","into","onto","upon","over","under",
        "above","below","between","among","through","during","before","after",
        "until","till","since","about","against","along","around","behind",
        "beneath","beside","besides","beyond","despite","except","inside",
        "outside","toward","towards","within","without","across","near","off",
        "past","per","via","because","although","though","while","whereas",
        "unless","whether","if","then","than","that","so",
        // Pronouns and determiners
        "i","you","he","she","it","we","they","me","him","her","us","them",
        "my","your","his","its","our","their","mine","yours","hers","ours",
        "theirs","myself","yourself","himself","herself","itself","ourselves",
        "themselves","this","these","those","who","whom","whose","which",
        "what","whatever","whoever","anyone","anybody","anything","everyone",
        "everybody","everything","someone","somebody","something","nobody",
        "nothing","none","each","either","neither","both","few","many","much",
        "most","more","less","least","other","another","such","same","own",
        "all","some","any","several","every",
        // Auxiliary and very common verbs
        "is","am","was","are","were","be","been","being","have","has","had",
        "having","do","does","did","doing","done","will","would","could",
        "should","may","might","must","shall","can","cannot","get","gets",
        "got","gotten","getting","said","says","say","went","goes","going",
        "gone","came","come","comes","coming","made","make","makes","making",
        "took","take","takes","taken","taking","put","puts","let","lets",
        // Adverbs and fillers
        "not","no","nor","only","just","also","very","too","quite","rather",
        "really","still","even","again","once","twice","never","always",
        "often","sometimes","usually","ever","yet","already","almost","enough",
        "perhaps","maybe","however","therefore","thus","hence","instead",
        "meanwhile","moreover","otherwise","anyway","indeed","further",
        "up","out","down","back","away","here","there","where","when","why",
        "how","then","now","soon","later","ago","far","well","else","away",
        // Numbers and misc
        "one","two","three","four","five","six","seven","eight","nine","ten",
        "first","second","third","last","next","new","old","own"
    ]

    init(text: String, chapters: [(title: String, charOffset: Int)] = []) {
        self.fullText = text
        self.chapters = chapters
        process()
    }

    /// Index of the chapter that contains `charPosition`
    /// (the last chapter whose offset is ≤ charPosition).
    func chapterIndex(for charPosition: Int) -> Int? {
        var result: Int? = nil
        for (i, ch) in chapters.enumerated() {
            if ch.charOffset <= charPosition { result = i } else { break }
        }
        return result
    }

    private func process() {
        tokenizeWords()
        tokenizeSentences()
        findRepeatedWords()
        computeChapterWordCounts()
    }

    private func computeChapterWordCounts() {
        guard !chapters.isEmpty else { return }
        let textLength = (fullText as NSString).length
        var counts: [Int] = []
        for (i, ch) in chapters.enumerated() {
            let start = ch.charOffset
            let end = i + 1 < chapters.count ? chapters[i + 1].charOffset : textLength
            counts.append(firstTokenIndex(atOrAfter: end) - firstTokenIndex(atOrAfter: start))
        }
        chapterWordCounts = counts
    }

    /// Index of the first word token starting at or after `pos` (binary search).
    private func firstTokenIndex(atOrAfter pos: Int) -> Int {
        var lo = 0, hi = wordTokens.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if wordTokens[mid].range.location < pos { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func tokenizeWords() {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = fullText
        var result: [WordToken] = []
        tokenizer.enumerateTokens(in: fullText.startIndex..<fullText.endIndex) { range, _ in
            let nsRange = NSRange(range, in: self.fullText)
            result.append(WordToken(text: String(self.fullText[range]), range: nsRange))
            return true
        }
        wordTokens = result
    }

    private func tokenizeSentences() {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = fullText
        var result: [Sentence] = []
        tokenizer.enumerateTokens(in: fullText.startIndex..<fullText.endIndex) { range, _ in
            let nsRange = NSRange(range, in: self.fullText)
            let wordsInSentence = self.wordTokens.filter {
                NSIntersectionRange($0.range, nsRange).length > 0
            }.map { $0.range }
            result.append(Sentence(range: nsRange, wordRanges: wordsInSentence))
            return true
        }
        sentences = result
    }

    private func findRepeatedWords() {
        var freq: [String: [Int]] = [:]
        for token in wordTokens {
            let lower = token.text.lowercased()
            guard !stopWords.contains(lower), lower.count > 2 else { continue }
            freq[lower, default: []].append(token.range.location)
        }
        var locations = Set<Int>()
        for (_, locs) in freq where locs.count > 1 {
            locs.forEach { locations.insert($0) }
        }
        repeatedWordLocations = locations
    }

    func sentenceIndex(for charPosition: Int) -> Int? {
        // Binary search — sentences are ordered and non-overlapping.
        var lo = 0, hi = sentences.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = sentences[mid].range
            if charPosition < r.location        { hi = mid - 1 }
            else if charPosition >= NSMaxRange(r) { lo = mid + 1 }
            else                                  { return mid   }
        }
        return nil
    }

    func wordToken(containing charPosition: Int) -> WordToken? {
        guard let i = wordTokenIndex(for: charPosition) else { return nil }
        return wordTokens[i]
    }

    func wordToken(at index: Int) -> WordToken? {
        guard index >= 0, index < wordTokens.count else { return nil }
        return wordTokens[index]
    }

    func wordTokenIndex(for charPosition: Int) -> Int? {
        // Binary search — word tokens are ordered and non-overlapping.
        var lo = 0, hi = wordTokens.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = wordTokens[mid].range
            if charPosition < r.location        { hi = mid - 1 }
            else if charPosition >= NSMaxRange(r) { lo = mid + 1 }
            else                                  { return mid   }
        }
        return nil
    }
}
