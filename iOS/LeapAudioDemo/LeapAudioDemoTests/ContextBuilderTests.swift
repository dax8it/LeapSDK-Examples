import XCTest
@testable import LeapAudioDemo

final class ContextBuilderTests: XCTestCase {
    func testExhibitContextIncludesExhibitAndArtworkTitles() {
        let exhibit = ExhibitMeta(
            id: "black-canvas",
            title: "Black Canvas",
            shortStatement: "A study in light.",
            coverImageName: "black-canvas-01.jpg",
            order: 1
        )

        let artist = Artist(
            name: "Alex Covo",
            mission: "Fashion photography as story.",
            bio: "NYC-based fashion photographer",
            themes: ["street", "editorial"]
        )

        let artwork = Artwork(
            id: "work-1",
            title: "First Light",
            year: "2021",
            medium: "Photography",
            summary: "Soft light across the subject.",
            story: "Captured at dawn.",
            technique: "Natural light",
            tags: ["portrait"],
            imageName: "work-1.jpg",
            quote: ""
        )

        let packet = ExhibitContextBuilder.buildContextPacket(
            exhibit: exhibit,
            artist: artist,
            artwork: artwork
        )

        XCTAssertTrue(packet.contains("Black Canvas"))
        XCTAssertTrue(packet.contains("First Light"))
        XCTAssertTrue(packet.contains("[Exhibit Context]"))
    }
}
