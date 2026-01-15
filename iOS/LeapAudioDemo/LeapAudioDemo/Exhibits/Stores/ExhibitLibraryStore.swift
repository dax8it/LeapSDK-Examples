import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ExhibitLibraryStore {
    private(set) var exhibits: [ExhibitMeta] = []
    private(set) var appHelp: AppHelp?
    private(set) var isLoaded = false
    private(set) var loadError: String?
    
    private(set) var activeExhibit: ExhibitMeta?
    private(set) var activeArtist: Artist?
    private(set) var activeWorks: [Artwork] = []
    
    var selectedArtwork: Artwork?
    
    // Debug logging
    var debugActiveExhibitID: String { activeExhibit?.id ?? "none" }
    var debugSelectedArtworkID: String { selectedArtwork?.id ?? "none" }
    
    /// Exhibits that have at least one work with a valid image
    var exhibitsWithImages: [ExhibitMeta] {
        exhibits.filter { exhibit in
            guard let imageName = exhibit.effectiveCoverImageName else { return false }
            return imageExists(named: imageName)
        }
    }
    
    func loadIndex() {
        guard !isLoaded else { return }
        
        do {
            let index: ExhibitIndex = try loadJSON("index", subdirectory: "Exhibits/Data")
            var loadedExhibits = index.exhibits.sorted { $0.order < $1.order }
            
            // Preload first work image for each exhibit to use as cover fallback
            for i in loadedExhibits.indices {
                let exhibitID = loadedExhibits[i].id
                if let firstImageName = loadFirstWorkImageName(for: exhibitID) {
                    loadedExhibits[i].firstWorkImageName = firstImageName
                    print("[ExhibitLibraryStore] 📷 Exhibit '\(exhibitID)' cover: \(firstImageName)")
                } else {
                    print("[ExhibitLibraryStore] ⚠️ Exhibit '\(exhibitID)' has no valid images")
                }
            }
            
            exhibits = loadedExhibits
            appHelp = try? loadJSON("app_help", subdirectory: "Exhibits/Data")
            isLoaded = true
            print("[ExhibitLibraryStore] ✅ Loaded \(exhibits.count) exhibits, \(exhibitsWithImages.count) with images")
        } catch {
            loadError = "Failed to load exhibit index: \(error.localizedDescription)"
            print("[ExhibitLibraryStore] ❌ \(loadError ?? "")")
        }
    }
    
    /// Load the first work's image name for an exhibit
    private func loadFirstWorkImageName(for exhibitID: String) -> String? {
        let worksPath = "Exhibits/Data/\(exhibitID)/works"
        guard let works: [Artwork] = try? loadJSONByPath(worksPath, as: [Artwork].self),
              let firstWork = works.first else {
            return nil
        }
        // Verify image actually exists
        return imageExists(named: firstWork.imageName) ? firstWork.imageName : nil
    }
    
    /// Check if an image exists in assets or bundle
    private func imageExists(named name: String) -> Bool {
        ImageLoader.artworkImageExists(named: name)
    }
    
    func selectExhibit(_ exhibit: ExhibitMeta) {
        print("[ExhibitLibraryStore] 📂 Selecting exhibit: \(exhibit.id)")
        activeExhibit = exhibit
        selectedArtwork = nil
        loadExhibitData(for: exhibit.id)
    }
    
    func selectExhibit(byID id: String) {
        guard let exhibit = exhibits.first(where: { $0.id == id }) else {
            print("[ExhibitLibraryStore] ⚠️ Exhibit not found: \(id)")
            return
        }
        selectExhibit(exhibit)
    }
    
    func clearActiveExhibit() {
        print("[ExhibitLibraryStore] 🧹 Clearing active exhibit")
        activeExhibit = nil
        activeArtist = nil
        activeWorks = []
        selectedArtwork = nil
    }
    
    func selectArtwork(_ artwork: Artwork) {
        print("[ExhibitLibraryStore] 🖼️ Selecting artwork: \(artwork.id)")
        selectedArtwork = artwork
    }
    
    func clearSelectedArtwork() {
        selectedArtwork = nil
    }
    
    func exhibit(byID id: String) -> ExhibitMeta? {
        exhibits.first { $0.id == id }
    }
    
    func artwork(byID id: String) -> Artwork? {
        activeWorks.first { $0.id == id }
    }
    
    private func loadExhibitData(for exhibitID: String) {
        do {
            let artistPath = "Exhibits/Data/\(exhibitID)/artist"
            let worksPath = "Exhibits/Data/\(exhibitID)/works"
            
            activeArtist = try? loadJSONByPath(artistPath, as: Artist.self)
            activeWorks = try loadJSONByPath(worksPath, as: [Artwork].self)
            
            print("[ExhibitLibraryStore] ✅ Loaded exhibit data: artist=\(activeArtist?.name ?? "nil"), works=\(activeWorks.count)")
        } catch {
            print("[ExhibitLibraryStore] ❌ Failed to load exhibit data for \(exhibitID): \(error)")
            activeArtist = nil
            activeWorks = []
        }
    }
    
    private func loadJSON<T: Decodable>(_ name: String, subdirectory: String) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory) else {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                throw ExhibitLibraryError.fileNotFound("\(subdirectory)/\(name).json")
            }
            return try decodeJSON(from: url)
        }
        return try decodeJSON(from: url)
    }
    
    private func loadJSONByPath<T: Decodable>(_ path: String, as type: T.Type) throws -> T {
        let components = path.split(separator: "/")
        let name = String(components.last ?? "")
        let subdirectory = components.dropLast().joined(separator: "/")
        
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory) else {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                throw ExhibitLibraryError.fileNotFound("\(path).json")
            }
            return try decodeJSON(from: url)
        }
        return try decodeJSON(from: url)
    }
    
    private func decodeJSON<T: Decodable>(from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
    
    func debugStatus() -> String {
        """
        [ExhibitLibraryStore]
        exhibits: \(exhibits.count)
        activeExhibit: \(activeExhibit?.id ?? "nil")
        activeArtist: \(activeArtist?.name ?? "nil")
        activeWorks: \(activeWorks.count)
        selectedArtwork: \(selectedArtwork?.id ?? "nil")
        """
    }
}

enum ExhibitLibraryError: LocalizedError {
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Could not find \(path) in bundle"
        }
    }
}
