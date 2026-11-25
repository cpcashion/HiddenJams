//
//  TasteProfileLaunchCrashTests.swift
//  HiddenJamsTests
//
//  App Review rejected 1.6.1 (91), Guideline 2.1(a): crash on launch on
//  iOS 27.2.1. Symbolicated: TasteProfileBuilder.swift:267, the first line
//  of TasteProfileFlowModel.run (`lines = [StageLine(...), ...]`), trapping
//  in swift_checkMetadataState while instantiating
//  _ContiguousArrayStorage<TasteProfileFlowModel.StageLine>.
//  These tests run that exact path; on an affected build/OS they crash the
//  test host instead of passing.
//

import Testing
import Foundation
@testable import HiddenJams

@MainActor
struct TasteProfileLaunchCrashTests {

    @Test func runListsAllSixStageLines() async throws {
        let model = TasteProfileFlowModel()
        model.minimumDwell = .zero
        model.hardCap = 1
        let apple = AppleMusicService()
        let analyzer = AIProfileAnalyzer(appleMusicService: apple)
        let task = Task {
            await model.run(sources: [.appleMusic], spotifyToken: nil,
                            analyzer: analyzer, spotifyAPI: SpotifyAPIService(),
                            appleMusic: apple)
        }
        let deadline = Date().addingTimeInterval(5)
        while model.lines.count < 6 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.lines.count == 6)
        task.cancel()
    }

    @Test func stageLineArrayAllocates() {
        let lines = TasteProfileFlowModel.Stage.allCases.map {
            TasteProfileFlowModel.StageLine(stage: $0, text: "x", state: .wait)
        }
        #expect(lines.count == 6)
    }
}
