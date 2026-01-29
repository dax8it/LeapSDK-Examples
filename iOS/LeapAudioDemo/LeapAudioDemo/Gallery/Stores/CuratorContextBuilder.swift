import Foundation

struct CuratorContextBuilder {
    
    /// Curator rules injected into user messages
    static let curatorInstructions = SystemPrompts.curatorRules
    
    static func buildContextPacket(artist: Artist?, artwork: Artwork?) -> String {
        var lines: [String] = ["[Exhibit Context]"]
        
        if let artist = artist {
            lines.append("Artist: \(artist.name)")
            if !artist.mission.isEmpty {
                let short = String(artist.mission.prefix(100))
                lines.append("Mission: \(short)")
            }
            if !artist.themes.isEmpty {
                lines.append("Themes: \(artist.themes.prefix(3).joined(separator: ", "))")
            }
        }
        
        if let artwork = artwork {
            lines.append("[Selected Artwork]")
            lines.append("Title: \(artwork.displayTitle)")
            if !artwork.year.isEmpty { lines.append("Year: \(artwork.year)") }
            if !artwork.medium.isEmpty { lines.append("Medium: \(artwork.medium)") }
            if !artwork.summary.isEmpty {
                let short = String(artwork.summary.prefix(120))
                lines.append("Summary: \(short)")
            }
            if !artwork.tags.isEmpty {
                lines.append("Tags: \(artwork.tags.prefix(4).joined(separator: ", "))")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    static func buildGeneralContextPacket(artist: Artist?, artworks: [Artwork]) -> String {
        var lines: [String] = ["[Exhibit Context]"]
        
        if let artist = artist {
            lines.append("Artist: \(artist.name)")
            if !artist.themes.isEmpty {
                lines.append("Themes: \(artist.themes.prefix(3).joined(separator: ", "))")
            }
        }
        
        if !artworks.isEmpty {
            let titles = artworks.compactMap { $0.title.isEmpty ? nil : $0.title }.prefix(8)
            lines.append("Works: \(titles.joined(separator: ", "))")
        }
        
        return lines.joined(separator: "\n")
    }
}
