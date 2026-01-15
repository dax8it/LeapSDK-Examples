import UIKit

enum ImageLoader {
    /// Load an artwork image by name, supporting both flat and exhibit-prefixed paths
    /// Examples:
    ///   - "work-01.jpg" → looks in Artworks/
    ///   - "black-canvas/bc-01.jpg" → looks in Artworks/black-canvas/
    static func loadArtworkImage(named name: String) -> UIImage? {
        let cleanName = name
            .replacingOccurrences(of: ".jpg", with: "")
            .replacingOccurrences(of: ".png", with: "")
        
        // Check if path contains a subdirectory (e.g., "black-canvas/bc-01")
        if cleanName.contains("/") {
            let components = cleanName.split(separator: "/")
            let directory = "Artworks/\(components.dropLast().joined(separator: "/"))"
            let fileName = String(components.last ?? "")
            
            // Check in exhibit-specific subdirectory
            if let path = Bundle.main.path(forResource: fileName, ofType: "jpg", inDirectory: directory) {
                return UIImage(contentsOfFile: path)
            }
            if let path = Bundle.main.path(forResource: fileName, ofType: "png", inDirectory: directory) {
                return UIImage(contentsOfFile: path)
            }
        }
        
        // Fallback: Check in Artworks/ root
        if let path = Bundle.main.path(forResource: cleanName, ofType: "jpg", inDirectory: "Artworks") {
            return UIImage(contentsOfFile: path)
        }
        
        // Fallback: Check bundle root
        if let path = Bundle.main.path(forResource: cleanName, ofType: "jpg") {
            return UIImage(contentsOfFile: path)
        }
        
        // Fallback: Check asset catalog
        if let asset = UIImage(named: cleanName) {
            return asset
        }
        
        return nil
    }
    
    /// Check if an artwork image exists
    static func artworkImageExists(named name: String) -> Bool {
        loadArtworkImage(named: name) != nil
    }
}
