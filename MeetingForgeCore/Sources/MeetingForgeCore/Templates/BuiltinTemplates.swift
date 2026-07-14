import Foundation

public struct BuiltinTemplate: Sendable {
    public let key: String
    public let name: String
    public let icon: String
    public let systemPrompt: String
    public let sections: [String]
}

public enum BuiltinTemplates {
    public static func template(forKey key: String) -> BuiltinTemplate? {
        all.first { $0.key == key }
    }

    public static let all: [BuiltinTemplate] = [
        BuiltinTemplate(
            key: "business",
            name: "Business Meeting",
            icon: "briefcase",
            systemPrompt: """
            You are an experienced executive assistant writing formal meeting minutes \
            (ata de reunião). Be precise and neutral. Attribute statements to speakers \
            when speaker labels are present. Capture decisions verbatim where possible. \
            For every action point include the owner (if identifiable) and any mentioned deadline. \
            Do not invent information that is not in the transcript.
            """,
            sections: ["Summary", "Participants", "Decisions", "Action Points",
                       "Open Questions", "Next Steps"]
        ),
        BuiltinTemplate(
            key: "it",
            name: "IT / Engineering Meeting",
            icon: "laptopcomputer",
            systemPrompt: """
            You are a senior engineering manager writing minutes for a technical meeting. \
            Preserve technical terms, system names, version numbers and error messages exactly \
            as spoken. Separate decisions from open technical debates. For action points, \
            include owner and affected system/component. List anything that requires further \
            research or a spike under Research. Do not invent information that is not in the transcript.
            """,
            sections: ["Summary", "Technical Decisions", "Action Points", "Blockers & Risks",
                       "Research / Spikes", "Open Questions"]
        ),
        BuiltinTemplate(
            key: "personal",
            name: "Personal / Informal",
            icon: "person.2",
            systemPrompt: """
            You are summarizing an informal conversation or personal planning session. \
            Keep the tone light and the summary short. Focus on what was agreed, who does what, \
            and anything to remember or look up later. Do not invent information that is not in \
            the transcript.
            """,
            sections: ["Summary", "To-Do", "Ideas", "To Look Up", "Reminders"]
        ),
    ]
}
