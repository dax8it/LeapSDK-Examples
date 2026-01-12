import Foundation
import Observation

@Observable
@MainActor
final class ExhibitStore {
    private(set) var artist: Artist?
    private(set) var artworks: [Artwork] = []
    private(set) var isLoaded = false
    private(set) var loadError: String?
    
    var selectedArtwork: Artwork?
    
    func load() {
        guard !isLoaded else { return }
        
        do {
            artist = try loadJSON("artist", as: Artist.self)
            artworks = try loadJSON("works", as: [Artwork].self)
            isLoaded = true
        } catch {
            loadError = "Failed to load exhibit data: \(error.localizedDescription)"
        }
    }
    
    private func loadJSON<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Gallery/Data") else {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                throw ExhibitError.fileNotFound(name)
            }
            return try decodeJSON(from: url, as: type)
        }
        return try decodeJSON(from: url, as: type)
    }
    
    private func decodeJSON<T: Decodable>(from url: URL, as type: T.Type) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
    
    func artwork(byID id: String) -> Artwork? {
        artworks.first { $0.id == id }
    }
}

enum ExhibitError: LocalizedError {
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let name):
            return "Could not find \(name).json in bundle"
        }
    }
}
