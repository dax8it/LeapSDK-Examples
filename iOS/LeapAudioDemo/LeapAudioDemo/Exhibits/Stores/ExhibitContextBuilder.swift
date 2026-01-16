import Foundation

struct ExhibitContextBuilder {
    
    /// Full system prompt with curator instructions embedded
    static let systemPrompt = """
Respond with interleaved text and audio. You are the voice curator for Alex Covo's photography exhibitions. \
Use ONLY the Exhibit Context provided. If a detail is not in the context, say you don't know. \
Do not invent titles, awards, locations, or backstory. Be concise - limit responses to 2-3 sentences. Never say you are Alex.
"""
    
    /// Legacy: kept for backward compatibility but should not be used in user messages
    static let curatorInstructions = ""
    
    static func buildContextPacket(
        exhibit: ExhibitMeta?,
        artist: Artist?,
        artwork: Artwork?
    ) -> String {
        var lines: [String] = ["[Exhibit Context]"]
        
        if let exhibit = exhibit {
            lines.append("[Gallery: \(exhibit.title)]")
            lines.append("Theme: \(String(exhibit.shortStatement.prefix(100)))")
        }
        
        if let artist = artist {
            lines.append("")
            lines.append("[Artist]")
            lines.append("Name: \(artist.name)")
            if !artist.mission.isEmpty {
                let short = String(artist.mission.prefix(100))
                lines.append("Mission: \(short)")
            }
            if !artist.themes.isEmpty {
                lines.append("Themes: \(artist.themes.prefix(3).joined(separator: ", "))")
            }
        }
        
        if let artwork = artwork {
            lines.append("")
            lines.append("[Selected Artwork]")
            lines.append("Title: \(artwork.displayTitle)")
            if !artwork.year.isEmpty { lines.append("Year: \(artwork.year)") }
            if !artwork.medium.isEmpty { lines.append("Medium: \(artwork.medium)") }
            if !artwork.summary.isEmpty {
                let short = String(artwork.summary.prefix(150))
                lines.append("Summary: \(short)")
            }
            if !artwork.story.isEmpty {
                let short = String(artwork.story.prefix(150))
                lines.append("Story: \(short)")
            }
            if !artwork.technique.isEmpty {
                let short = String(artwork.technique.prefix(100))
                lines.append("Technique: \(short)")
            }
            if !artwork.tags.isEmpty {
                lines.append("Tags: \(artwork.tags.prefix(5).joined(separator: ", "))")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    static func buildGeneralExhibitContext(
        exhibit: ExhibitMeta?,
        artist: Artist?,
        artworks: [Artwork]
    ) -> String {
        var lines: [String] = ["[Exhibit Context]"]
        
        if let exhibit = exhibit {
            lines.append("[Gallery: \(exhibit.title)]")
            lines.append("Theme: \(exhibit.shortStatement)")
        }
        
        if let artist = artist {
            lines.append("")
            lines.append("[Artist]")
            lines.append("Name: \(artist.name)")
            if !artist.themes.isEmpty {
                lines.append("Themes: \(artist.themes.prefix(3).joined(separator: ", "))")
            }
        }
        
        if !artworks.isEmpty {
            lines.append("")
            lines.append("[Works in this gallery]")
            let titles = artworks.compactMap { $0.title.isEmpty ? nil : $0.title }.prefix(10)
            lines.append("Titles: \(titles.joined(separator: ", "))")
        }
        
        return lines.joined(separator: "\n")
    }
    
    static func buildAutoTourContext(
        exhibit: ExhibitMeta?,
        artist: Artist?,
        artwork: Artwork
    ) -> String {
        var lines: [String] = ["[Auto Tour Context]"]
        
        if let exhibit = exhibit {
            lines.append("Gallery: \(exhibit.title)")
        }
        
        if let artist = artist {
            lines.append("Artist: \(artist.name)")
        }
        
        lines.append("")
        lines.append("[Current Artwork]")
        lines.append("Title: \(artwork.displayTitle)")
        if !artwork.summary.isEmpty {
            lines.append("Summary: \(artwork.summary)")
        }
        if !artwork.story.isEmpty {
            let short = String(artwork.story.prefix(200))
            lines.append("Story: \(short)")
        }
        if !artwork.technique.isEmpty {
            lines.append("Technique: \(artwork.technique)")
        }
        
        return lines.joined(separator: "\n")
    }
}
