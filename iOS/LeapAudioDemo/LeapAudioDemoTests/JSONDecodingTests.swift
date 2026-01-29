import XCTest
@testable import LeapAudioDemo

final class JSONDecodingTests: XCTestCase {
    func testIndexJSONDecodes() throws {
        let json = """
        {
          "exhibits": [
            {
              "id": "black-canvas",
              "title": "Black Canvas",
              "shortStatement": "A study in light and shadow.",
              "coverImageName": "black-canvas-01.jpg",
              "order": 1
            },
            {
              "id": "moon-rising",
              "title": "Moon Rising",
              "shortStatement": "Night portraits under moonlight.",
              "coverImageName": "moon-rising-01.jpg",
              "order": 2
            }
          ]
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ExhibitIndex.self, from: data)

        XCTAssertEqual(decoded.exhibits.count, 2)
        XCTAssertEqual(decoded.exhibits[0].id, "black-canvas")
        XCTAssertEqual(decoded.exhibits[1].title, "Moon Rising")
        XCTAssertEqual(decoded.exhibits[0].order, 1)
    }

    func testWorksJSONDecodes() throws {
        let json = """
        [
          {
            "id": "work-1",
            "title": "First Light",
            "year": "2021",
            "medium": "Photography",
            "summary": "Soft light across the subject.",
            "story": "Captured at dawn.",
            "technique": "Natural light",
            "tags": ["portrait"],
            "imageName": "work-1.jpg",
            "quote": ""
          },
          {
            "id": "work-2",
            "title": "Shadow Study",
            "year": "2022",
            "medium": "Photography",
            "summary": "A play of shadow and form.",
            "story": "Studio series.",
            "technique": "Strobe",
            "tags": ["studio"],
            "imageName": "work-2.jpg",
            "quote": ""
          }
        ]
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode([Artwork].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.first?.id, "work-1")
        XCTAssertEqual(decoded.last?.imageName, "work-2.jpg")
    }

    func testArtistJSONDecodes() throws {
        let json = """
        {
          "name": "Alex Covo",
          "mission": "Fashion photography as story.",
          "bio": "NYC-based fashion photographer",
          "themes": ["street", "editorial"]
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(Artist.self, from: data)

        XCTAssertEqual(decoded.name, "Alex Covo")
        XCTAssertEqual(decoded.themes.count, 2)
    }
}
