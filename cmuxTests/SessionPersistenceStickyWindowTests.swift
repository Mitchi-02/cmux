import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class SessionPersistenceStickyWindowTests: XCTestCase {
    private func makeWindowSnapshot(isSticky: Bool?) -> SessionWindowSnapshot {
        SessionWindowSnapshot(
            windowId: UUID(),
            frame: nil,
            display: nil,
            tabManager: SessionTabManagerSnapshot(selectedWorkspaceIndex: 0, workspaces: []),
            sidebar: SessionSidebarSnapshot(isVisible: true, selection: .tabs, width: 240),
            isStickyTerminal: isSticky
        )
    }

    func testStickyFlagRoundTrips() throws {
        let snapshot = makeWindowSnapshot(isSticky: true)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionWindowSnapshot.self, from: data)
        XCTAssertEqual(decoded.isStickyTerminal, true)
    }

    func testLegacySnapshotWithoutFlagDecodesAsNil() throws {
        // A snapshot written by an older build has no isStickyTerminal key.
        let json = """
        {
          "windowId": "\(UUID().uuidString)",
          "tabManager": { "workspaces": [] },
          "sidebar": { "isVisible": true, "selection": "tabs" }
        }
        """
        let decoded = try JSONDecoder().decode(
            SessionWindowSnapshot.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(decoded.isStickyTerminal)
    }

    func testStandardWindowEncodesNilFlag() throws {
        let snapshot = makeWindowSnapshot(isSticky: nil)
        let data = try JSONEncoder().encode(snapshot)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // Optional nil is omitted, keeping the payload backward-compatible.
        XCTAssertNil(object?["isStickyTerminal"])
    }
}
