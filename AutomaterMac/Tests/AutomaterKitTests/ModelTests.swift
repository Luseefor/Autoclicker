import XCTest
@testable import AutomaterKit

final class ModelTests: XCTestCase {
    func testMacroStepRoundTripsPythonSchema() throws {
        let json = """
        {"type":"click","x":5,"y":6,"button":"left","delay_ms":50,
         "coord_space":"window","app_name":"Safari","window_id":99,
         "local_x":1.0,"local_y":2.0,"click_kind":"double"}
        """.data(using: .utf8)!

        let step = try JSONDecoder().decode(MacroStep.self, from: json)
        XCTAssertEqual(step.type, "click")
        XCTAssertEqual(step.x, 5)
        XCTAssertEqual(step.coordSpace, "window")
        XCTAssertEqual(step.windowId, 99)
        XCTAssertEqual(step.localX, 1.0)
        XCTAssertEqual(step.clickKind, "double")

        let out = try JSONEncoder().encode(step)
        let back = try JSONDecoder().decode(MacroStep.self, from: out)
        XCTAssertEqual(back, step)
    }

    func testMacroDecodesPythonFileShape() throws {
        let json = """
        {"id":"abc123","name":"Test","loop_count":3,"speed":1.5,
         "target_app_name":"Safari","activate_before_play":false,
         "steps":[{"type":"delay","delay_ms":100}]}
        """.data(using: .utf8)!
        let macro = try JSONDecoder().decode(Macro.self, from: json)
        XCTAssertEqual(macro.id, "abc123")
        XCTAssertEqual(macro.loopCount, 3)
        XCTAssertEqual(macro.speed, 1.5, accuracy: 0.001)
        XCTAssertFalse(macro.activateBeforePlay)
        XCTAssertEqual(macro.steps.first?.delayMs, 100)
    }

    func testClickKindPressExpansion() {
        XCTAssertEqual(ClickKind.single.presses, 1)
        XCTAssertEqual(ClickKind.double.presses, 2)
        XCTAssertEqual(ClickKind.triple.presses, 3)
    }
}
