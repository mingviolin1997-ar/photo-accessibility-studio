import XCTest
@testable import PhotoAccessibilityStudio

final class PromptTests: XCTestCase {
    func testRuntimeProgressShowsTransferredBytesAndSpeed() {
        let progress = RuntimeProgress(step: "下载模型",
                                       downloaded: 1_500_000,
                                       total: 3_000_000,
                                       bytesPerSecond: 500_000)
        XCTAssertEqual(progress.fraction, 0.5)
        XCTAssertTrue(progress.detail.contains("/"))
        XCTAssertTrue(progress.detail.contains("/秒"))
    }

    func testRuntimeErrorsIncludeDiagnosticValue() {
        XCTAssertEqual(RuntimeSetupError.downloadFailed("HTTP 500").errorDescription,
                       "下载失败：HTTP 500")
    }

    func testSanitizeRemovesKnownHeadingAndWhitespace() {
        XCTAssertEqual(
            AccessibilityDescriptionPrompt.sanitize("  无障碍描述：一只黑猫坐在窗边。\n"),
            "一只黑猫坐在窗边。"
        )
    }

    func testStatusLabelsAreDistinctAndNonempty() {
        let labels = JobStatus.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, JobStatus.allCases.count)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }

    func testNewPhotoIsSelectedForAutomaticWritingByDefault() {
        let job = PhotoJob(url: URL(fileURLWithPath: "/tmp/example.jpg"))
        XCTAssertTrue(job.isApproved)
    }

    func testEveryDescriptionStyleHasAUniquePrompt() {
        let prompts = DescriptionStyle.allCases.map {
            AccessibilityDescriptionPrompt.chinese(
                preferences: .init(style: $0, includeCaptureAdvice: false)
            )
        }
        XCTAssertEqual(Set(prompts).count, DescriptionStyle.allCases.count)
        XCTAssertTrue(prompts.allSatisfy { $0.contains("准确性优先") })
    }

    func testAdviceSwitchChangesStructuredInstruction() {
        let enabled = AccessibilityDescriptionPrompt.chinese(
            preferences: .init(style: .medium, includeCaptureAdvice: true)
        )
        let disabled = AccessibilityDescriptionPrompt.chinese(
            preferences: .init(style: .medium, includeCaptureAdvice: false)
        )
        XCTAssertTrue(enabled.contains("下次能直接照做"))
        XCTAssertTrue(enabled.contains("主体可辨识度"))
        XCTAssertTrue(enabled.contains("不要为了审美建议增加复杂背景"))
        XCTAssertTrue(disabled.contains("advice 字段必须是空字符串"))
    }
}
