import Foundation

struct SSEEvent: Equatable, Sendable {
    var event: String?
    var data: String
    var id: String?
}

struct SSEParser: Sendable {
    private var buffer = ""

    mutating func feed(_ string: String) -> [SSEEvent] {
        buffer.append(string)
        var events: [SSEEvent] = []

        while let range = buffer.range(of: "\n\n") ?? buffer.range(of: "\r\n\r\n") {
            let chunk = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            if let event = parseBlock(chunk) {
                events.append(event)
            }
        }
        return events
    }

    mutating func flush() -> SSEEvent? {
        defer { buffer = "" }
        let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remaining.isEmpty else { return nil }
        return parseBlock(remaining)
    }

    private func parseBlock(_ block: String) -> SSEEvent? {
        var event: String?
        var id: String?
        var dataLines: [String] = []

        let lines = block.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        for raw in lines {
            let line = String(raw)
            if line.isEmpty || line.hasPrefix(":") { continue }
            guard let colon = line.firstIndex(of: ":") else {
                dataLines.append(line)
                continue
            }
            let field = String(line[..<colon])
            var value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
            switch field {
            case "event": event = value
            case "data": dataLines.append(value)
            case "id": id = value
            default: break
            }
        }

        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: event, data: dataLines.joined(separator: "\n"), id: id)
    }
}
