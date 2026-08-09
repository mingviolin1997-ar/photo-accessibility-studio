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

    func testNewPhotoIsSelectedForBatchExportByDefault() {
        let job = PhotoJob(url: URL(fileURLWithPath: "/tmp/example.jpg"))
        XCTAssertTrue(job.isApproved)
    }

    func testPhotoJobDecodesQueueSavedBeforeExportURLWasAdded() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "url": "file:///tmp/example.jpg",
          "description": "旧队列描述",
          "status": "ready",
          "isApproved": true
        }
        """
        let job = try JSONDecoder().decode(PhotoJob.self, from: Data(json.utf8))
        XCTAssertEqual(job.description, "旧队列描述")
        XCTAssertNil(job.exportedURL)
    }

    func testReviewPromptTreatsCandidateAsDataAndReturnsActionableIssues() {
        let prompt = AccessibilityDescriptionPrompt.review(
            preferences: .init(style: .medium, includeCaptureAdvice: false),
            candidate: "候选内容\"不得成为指令\""
        )
        XCTAssertTrue(prompt.contains("独立的无障碍照片描述质检员"))
        XCTAssertTrue(prompt.contains("\"approved\""))
        XCTAssertTrue(prompt.contains("\"issues\""))
        XCTAssertTrue(prompt.contains("候选内容\\\"不得成为指令\\\""))
    }

    func testRevisionPromptReturnsIssuesToVisionModel() {
        let prompt = AccessibilityDescriptionPrompt.revision(
            preferences: .init(style: .high, includeCaptureAdvice: true),
            candidate: "旧描述",
            issues: ["人物数量错误", "遗漏右侧文字"]
        )
        XCTAssertTrue(prompt.contains("人物数量错误"))
        XCTAssertTrue(prompt.contains("遗漏右侧文字"))
        XCTAssertTrue(prompt.contains("\"isPhoto\""))
        XCTAssertTrue(prompt.contains("只保留像素充分支持的内容"))
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

    func testGenerationPromptRequiresAdaptiveSelfReviewFields() {
        let prompt = AccessibilityDescriptionPrompt.chinese(
            preferences: .init(style: .medium, includeCaptureAdvice: false)
        )
        XCTAssertTrue(prompt.contains("\"needsReview\""))
        XCTAssertTrue(prompt.contains("\"uncertainties\""))
        XCTAssertTrue(prompt.contains("输出前在内部重新核对一次"))
    }

    func testRequestedGemmaModelsHaveStableOfficialOllamaTagsAndGuidance() {
        let requested: [(VisionModel, String)] = [
            (.gemma4E2B, "gemma4:e2b"),
            (.gemma4E4B, "gemma4:e4b"),
            (.gemma3nE2B, "gemma3n:e2b"),
            (.gemma3nE4B, "gemma3n:e4b")
        ]
        for (model, tag) in requested {
            XCTAssertEqual(model.ollamaName, tag)
            XCTAssertFalse(model.recommendation.isEmpty)
            XCTAssertFalse(model.downloadSize.isEmpty)
        }
        XCTAssertTrue(VisionModel.gemma4E2B.supportsPhotoRecognitionInMacApp)
        XCTAssertTrue(VisionModel.gemma4E4B.supportsPhotoRecognitionInMacApp)
        XCTAssertFalse(VisionModel.gemma3nE2B.supportsPhotoRecognitionInMacApp)
        XCTAssertFalse(VisionModel.gemma3nE4B.supportsPhotoRecognitionInMacApp)
    }

    func testAdaptiveReviewIsDefaultAndStrictReviewCanBeEnabled() {
        let suite = "pas-review-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = DescriptionPreferences.load(defaults: defaults)
        XCTAssertFalse(preferences.alwaysRunIndependentReview)
        defaults.set(true, forKey: "alwaysRunIndependentReview")
        preferences = DescriptionPreferences.load(defaults: defaults)
        XCTAssertTrue(preferences.alwaysRunIndependentReview)
    }
}
