// Распознавание кода в тексте из буфера и его подсветка в предпросмотре.
// Без словарей языков и сторонних библиотек: один проход по символам, общие для
// большинства языков лексемы (строки, комментарии, числа, ключевые слова, типы, вызовы).
import AppKit
import SwiftUI

enum Code {
    private static let keywords: Set<String> = [
        "func", "let", "var", "if", "else", "for", "while", "return", "import", "class", "struct", "enum",
        "protocol", "extension", "guard", "switch", "case", "default", "break", "continue", "in", "do", "try",
        "catch", "throw", "throws", "async", "await", "static", "private", "public", "internal", "fileprivate",
        "final", "override", "init", "self", "nil", "true", "false", "def", "lambda", "None", "True", "False",
        "elif", "from", "as", "with", "pass", "yield", "const", "function", "new", "this", "null", "undefined",
        "typeof", "export", "interface", "type", "extends", "implements", "package", "go", "defer", "chan",
        "map", "range", "select", "void", "int", "char", "float", "double", "bool", "string", "unsigned",
        "long", "short", "namespace", "using", "template", "typename", "fn", "mut", "impl", "trait", "pub",
        "use", "match", "where", "then", "fi", "done", "esac", "and", "or", "not", "is",
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "JOIN", "ON", "CREATE", "TABLE",
        "ALTER", "DROP", "AND", "OR", "NOT", "NULL", "AS", "ORDER", "BY", "GROUP", "LIMIT", "VALUES", "SET",
    ]
    /// Слова, с которых обычно начинается строка кода.
    private static let lineStarters: Set<String> = [
        "func", "def", "class", "struct", "enum", "import", "from", "let", "var", "const", "return", "if",
        "for", "while", "switch", "case", "public", "private", "static", "package", "fn", "impl", "use",
        "function", "export", "type", "interface", "guard", "else", "try", "catch", "protocol", "extension",
        "SELECT", "INSERT", "UPDATE", "CREATE", "ALTER", "#include", "#define", "#import", "#!/bin/sh",
    ]
    private static let operators = ["->", "=>", "==", "!=", "&&", "||", ":=", "::", "+=", "</", "/>"]

    /// Похоже ли на код. Проверяются первые 200 строк.
    static func looksLikeCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return false }
        if let first = trimmed.first, let last = trimmed.last,
           (first == "{" && last == "}") || (first == "[" && last == "]"), trimmed.contains("\":") {
            return true  // JSON
        }
        var lines = 0, starters = 0, structural = 0
        for raw in trimmed.split(separator: "\n", omittingEmptySubsequences: true).prefix(200) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            lines += 1
            let head = line.prefix { !$0.isWhitespace && $0 != "(" && $0 != "{" && $0 != ":" }
            if lineStarters.contains(String(head)) || (line.hasPrefix("@") && head.count > 1) { starters += 1 }
            if let end = line.last, "{};".contains(end) { structural += 1 }
            else if operators.contains(where: { line.contains($0) }) || hasCall(line) { structural += 1 }
        }
        guard structural >= 1 else { return false }
        if lines == 1 { return starters == 1 }
        return starters + structural >= 3 && (starters + structural) * 2 >= lines
    }

    /// Есть ли вызов вида `name(` — скобка сразу после идентификатора.
    private static func hasCall(_ line: String) -> Bool {
        var prev: Character = " "
        for ch in line {
            if ch == "(" && (prev.isLetter || prev == "_") && prev.isASCII { return true }
            prev = ch
        }
        return false
    }

    static func highlight(_ text: String) -> AttributedString {
        let s = Array(text)
        let n = s.count
        var out = AttributedString()
        var plain = ""
        func flush() {
            if !plain.isEmpty { out.append(AttributedString(plain)); plain = "" }
        }
        func emit(_ from: Int, _ to: Int, _ color: NSColor) {
            flush()
            var part = AttributedString(String(s[from..<to]))
            part.foregroundColor = Color(nsColor: color)
            out.append(part)
        }
        func isIdent(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

        var i = 0
        while i < n {
            let c = s[i]
            let next: Character? = i + 1 < n ? s[i + 1] : nil
            let lineStart = i == 0 || s[i - 1] == "\n" || s[i - 1] == " " || s[i - 1] == "\t"
            if c == "/" && next == "/" || (c == "#" && lineStart && (next == " " || next == "!"))
                || (c == "-" && next == "-" && lineStart) {
                var j = i
                while j < n && s[j] != "\n" { j += 1 }
                emit(i, j, .secondaryLabelColor); i = j
            } else if c == "/" && next == "*" {
                var j = i + 2
                while j < n && !(s[j] == "/" && s[j - 1] == "*" && j > i + 2) { j += 1 }
                j = min(j + 1, n)
                emit(i, j, .secondaryLabelColor); i = j
            } else if c == "\"" || c == "'" || c == "`" {
                var j = i + 1
                while j < n && s[j] != c && (c == "`" || s[j] != "\n") { j += s[j] == "\\" ? 2 : 1 }
                j = min(j + 1, n)
                emit(i, j, .systemOrange); i = j
            } else if c.isNumber && c.isASCII && (i == 0 || !isIdent(s[i - 1])) {
                var j = i
                while j < n && (isIdent(s[j]) || s[j] == ".") { j += 1 }
                emit(i, j, .systemPurple); i = j
            } else if c.isLetter || c == "_" || c == "#" || c == "@" {
                var j = i + 1
                while j < n && isIdent(s[j]) { j += 1 }
                let word = String(s[i..<j])
                if keywords.contains(word) || ((c == "#" || c == "@") && j > i + 1) { emit(i, j, .systemPink) }
                else if j < n && s[j] == "(" { emit(i, j, .systemBlue) }
                else if c.isUppercase && c.isASCII && word.count > 1 { emit(i, j, .systemTeal) }
                else { plain += word }
                i = j
            } else {
                plain.append(c); i += 1
            }
        }
        flush()
        return out
    }
}
