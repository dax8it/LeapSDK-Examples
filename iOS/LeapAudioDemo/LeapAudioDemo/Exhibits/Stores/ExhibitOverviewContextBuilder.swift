import Foundation

struct ExhibitOverviewContextBuilder {
    
    /// Full system prompt with curator instructions embedded
    static let systemPrompt = """
Respond with interleaved text and audio. You are the voice curator for Alex Covo's photography exhibitions. \
Use ONLY the Exhibit Context provided. If a detail is not in the context, say you don't know. \
Do not invent titles, awards, locations, or backstory. Be concise - limit responses to 2-3 sentences. Never say you are Alex.
"""
    
    /// Legacy: kept for backward compatibility but should not be used in user messages
    static let curatorInstructions = ""
    
    static func buildContextPacket(
        exhibits: [ExhibitMeta],
        artist: Artist?
    ) -> String {
        var lines: [String] = ["[Exhibit Context - Galleries Overview]"]
        
        if let artist = artist {
            lines.append("[Artist]")
            lines.append("Name: \(artist.name)")
            if !artist.mission.isEmpty {
                let short = String(artist.mission.prefix(100))
                lines.append("Mission: \(short)")
            }
        }
        
        lines.append("")
        lines.append("[Available Galleries - Full Details]")
        for exhibit in exhibits {
            lines.append("")
            lines.append("[\(exhibit.title)]")
            lines.append("ID: \(exhibit.id)")
            lines.append("About: \(exhibit.shortStatement)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    static func buildSingleExhibitContext(exhibit: ExhibitMeta, artist: Artist?) -> String {
        var lines: [String] = ["[Exhibit Context - Gallery Info]"]
        
        if let artist = artist {
            lines.append("Artist: \(artist.name)")
        }
        
        lines.append("")
        lines.append("[Gallery: \(exhibit.title)]")
        lines.append("ID: \(exhibit.id)")
        lines.append("About: \(exhibit.shortStatement)")
        
        return lines.joined(separator: "\n")
    }
}
