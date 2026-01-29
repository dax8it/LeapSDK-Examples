import Foundation

struct ExhibitOverviewContextBuilder {
    
    /// Curator rules injected into user messages
    static let curatorInstructions = SystemPrompts.curatorRules
    
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
