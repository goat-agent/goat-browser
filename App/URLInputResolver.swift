import Foundation

// URLInputResolver — turns a raw command-bar string into a navigable URL.
//
// Rules (in order):
//   * If the input already has a URL scheme (http, https, file, about, data,
//     etc.), use it verbatim.
//   * about:* and localhost / IP / host(.tld)[/path] are treated as URLs and
//     get https:// prepended when no scheme is present.
//   * Anything else becomes a Google search.
//
// Pure, dependency-free, and unit-testable.
enum URLInputResolver {
    static func resolve(_ rawInput: String) -> URL? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if treatAsURL(input) {
            let withScheme = hasScheme(input) ? input : "https://\(input)"
            if let url = URL(string: withScheme) {
                return url
            }
            // Fall through to search if it somehow failed to parse.
        }
        return searchURL(for: input)
    }

    // MARK: - Classification

    static func treatAsURL(_ input: String) -> Bool {
        if hasScheme(input) {
            return true
        }
        // about: is handled by the scheme check above, but bare "about:blank"
        // also has a scheme. Guard anyway.
        if input.hasPrefix("about:") {
            return true
        }

        // Contains a space => almost certainly a search query.
        if input.contains(" ") {
            return false
        }

        // Strip any path/query/fragment to inspect just the host[:port] part.
        let hostPart = input.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" })
            .first.map(String.init) ?? input
        let host = hostPart.split(separator: ":").first.map(String.init) ?? hostPart

        if host.isEmpty {
            return false
        }

        // localhost is a URL.
        if host == "localhost" {
            return true
        }
        // IPv4 / bracketed IPv6.
        if isIPv4(host) || host.hasPrefix("[") {
            return true
        }
        // host with a dot and a plausible TLD (e.g. example.com, a.b.co.uk).
        if host.contains(".") {
            let labels = host.split(separator: ".")
            if let tld = labels.last, labels.count >= 2,
               tld.count >= 2, tld.allSatisfy({ $0.isLetter }) {
                return true
            }
        }
        return false
    }

    static func hasScheme(_ input: String) -> Bool {
        // scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ":"
        guard let colon = input.firstIndex(of: ":") else { return false }
        let scheme = input[input.startIndex..<colon]
        guard let first = scheme.first, first.isLetter, !scheme.isEmpty else {
            return false
        }
        // Avoid treating "localhost:8080" as a scheme — require it not be all
        // digits after the colon when scheme would be a bare hostname. A real
        // scheme is followed by "//" or a non-numeric value for our purposes.
        let afterColon = input[input.index(after: colon)...]
        if afterColon.first == "/" {
            return true
        }
        // "about:blank", "mailto:x", "data:..." — scheme with non-slash body.
        // But "localhost:8080" should NOT be a scheme. Heuristic: if everything
        // after the colon is digits (a port), it's a host:port, not a scheme.
        if afterColon.allSatisfy({ $0.isNumber }) && !afterColon.isEmpty {
            return false
        }
        return scheme.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
    }

    static func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let n = Int(part), part.allSatisfy({ $0.isNumber }) else { return false }
            return n >= 0 && n <= 255
        }
    }

    static func searchURL(for query: String) -> URL? {
        SearchEngine.current.url(for: query)
    }
}
