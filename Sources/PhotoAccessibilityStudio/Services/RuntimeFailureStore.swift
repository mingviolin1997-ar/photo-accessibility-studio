import Foundation

struct RuntimeFailureRecord: Codable, Equatable {
    let engine: String
    let model: String
    let reason: String
    let date: Date
}

enum RuntimeFailureStore {
    private static let key = "lastRuntimeSetupFailureV2"

    static func save(engine: InferenceEngine,
                     model: VisionModel,
                     reason: String,
                     defaults: UserDefaults = .standard,
                     date: Date = Date()) {
        let concise = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        let record = RuntimeFailureRecord(engine: engine.rawValue,
                                          model: model.rawValue,
                                          reason: concise,
                                          date: date)
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: key)
        }
    }

    static func matching(engine: InferenceEngine,
                         model: VisionModel,
                         defaults: UserDefaults = .standard) -> RuntimeFailureRecord? {
        guard let data = defaults.data(forKey: key),
              let record = try? JSONDecoder().decode(RuntimeFailureRecord.self, from: data),
              record.engine == engine.rawValue,
              record.model == model.rawValue else { return nil }
        return record
    }

    static func clear(engine: InferenceEngine,
                      model: VisionModel,
                      defaults: UserDefaults = .standard) {
        guard matching(engine: engine, model: model, defaults: defaults) != nil else { return }
        defaults.removeObject(forKey: key)
    }
}
