import Foundation

public struct TemplateContent: Sendable {
    public var name: String
    public var systemPrompt: String
    public var sections: [String]

    public init(name: String, systemPrompt: String, sections: [String]) {
        self.name = name
        self.systemPrompt = systemPrompt
        self.sections = sections
    }
}

public enum PromptBuilder {
    public static func build(
        template: TemplateContent,
        transcript: [TranscriptSegment],
        speakerNames: [String: String],
        diarized: Bool
    ) -> (system: String, user: String) {
        let sectionList = template.sections.map { "- \($0)" }.joined(separator: "\n")
        let system = """
        \(template.systemPrompt)

        Produce meeting minutes in Markdown with exactly these sections (use ## headings, keep this order, omit a section only if truly empty):
        \(sectionList)

        Write the minutes in the same language as the transcript.
        """

        let lines = transcript.map { segment -> String in
            let stamp = timestamp(segment.start)
            if diarized, let raw = segment.speaker {
                let name = speakerNames[raw] ?? raw
                return "[\(stamp)] \(name): \(segment.text)"
            }
            return "[\(stamp)] \(segment.text)"
        }
        let user = """
        Transcript of the meeting:

        \(lines.joined(separator: "\n"))
        """
        return (system, user)
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
