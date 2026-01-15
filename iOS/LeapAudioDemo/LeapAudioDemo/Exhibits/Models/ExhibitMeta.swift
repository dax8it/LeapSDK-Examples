import Foundation

struct ExhibitMeta: Codable, Identifiable {
    let id: String
    let title: String
    let shortStatement: String
    let coverImageName: String?
    let order: Int
    
    // Populated at runtime from first work in exhibit
    var firstWorkImageName: String?
    
    var displayTitle: String {
        title.isEmpty ? id : title
    }
    
    /// Returns the best available cover image name (explicit cover or first work)
    var effectiveCoverImageName: String? {
        coverImageName ?? firstWorkImageName
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, shortStatement, coverImageName, order
    }
}

struct ExhibitIndex: Codable {
    let exhibits: [ExhibitMeta]
}
