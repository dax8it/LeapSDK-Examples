import Foundation

struct ExhibitMeta: Codable, Identifiable {
    let id: String
    let title: String
    let shortStatement: String
    let coverImageName: String?
    let order: Int
    
    var displayTitle: String {
        title.isEmpty ? id : title
    }
}

struct ExhibitIndex: Codable {
    let exhibits: [ExhibitMeta]
}
