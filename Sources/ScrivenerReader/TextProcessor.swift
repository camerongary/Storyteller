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

    private let stopWords: Set<String> = [
        "the","a","an","and","or","but","in","on","at","to","for","of","with",
        "by","from","is","was","are","were","be","been","being","have","has",
        "had","do","does","did","will","would","could","should","may","might",
        "shall","i","you","he","she","it","we","they","me","him","her","us",
        "them","my","your","his","its","our","their","this","that","these",
        "those","not","no","as","if","so","then","than","when","where","who",
        "what","which","up","out","about","into","through","after","before",
        "just","also","very","more","can","one","two","all","some","any","said"
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
