import Foundation

struct HomeContextBuilder {
    
    /// Curator rules injected into user messages
    static let curatorInstructions = SystemPrompts.curatorRules
    
    static func buildContextPacket(
        artist: Artist?,
        exhibits: [ExhibitMeta],
        appHelp: AppHelp?
    ) -> String {
        var lines: [String] = ["[Exhibit Context - Home]"]
        
        if let artist = artist {
            lines.append("[Artist]")
            lines.append("Name: \(artist.name)")
            if !artist.mission.isEmpty {
                let short = String(artist.mission.prefix(150))
                lines.append("Mission: \(short)")
            }
            if !artist.themes.isEmpty {
                lines.append("Themes: \(artist.themes.prefix(4).joined(separator: ", "))")
            }
        }
        
        if !exhibits.isEmpty {
            lines.append("")
            lines.append("[Available Galleries]")
            for exhibit in exhibits.prefix(6) {
                lines.append("• \(exhibit.title): \(String(exhibit.shortStatement.prefix(80)))")
            }
        }
        
        if let help = appHelp {
            lines.append("")
            lines.append("[App Guide]")
            lines.append(help.content)
        }
        
        return lines.joined(separator: "\n")
    }
    
    static func buildArtistOnlyContext(artist: Artist?) -> String {
        var lines: [String] = ["[Exhibit Context - Artist Info]"]
        
        if let artist = artist {
            lines.append("Name: \(artist.name)")
            lines.append("Mission: \(artist.mission)")
            lines.append("Bio: \(artist.bio)")
            if !artist.themes.isEmpty {
                lines.append("Themes: \(artist.themes.joined(separator: ", "))")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}
