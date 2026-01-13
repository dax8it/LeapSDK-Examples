import Foundation

struct Artwork: Codable, Identifiable {
    let id: String
    let title: String
    let year: String
    let medium: String
    let summary: String
    let story: String
    let technique: String
    let tags: [String]
    let imageName: String
    let quote: String?
    
    var displayTitle: String {
        title.isEmpty ? id : title
    }
    
    var hasMetadata: Bool {
        !title.isEmpty || !summary.isEmpty || !story.isEmpty
    }
}
