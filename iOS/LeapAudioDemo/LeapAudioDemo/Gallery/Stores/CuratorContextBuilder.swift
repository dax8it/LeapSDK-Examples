import Foundation

struct CuratorContextBuilder {
    
    static let systemPrompt = "Respond with interleaved text and audio."
    
    static let curatorInstructions = """
You are the exhibition curator. Use ONLY the provided Exhibit Context. \
If the answer is not in the context, say you don't know. Do not invent details. Keep answers concise.
"""
    
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
