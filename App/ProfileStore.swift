import Foundation

enum ProfileStore {
    private static let profilesKey = "GoatProfiles"
    private static let activeKey = "GoatActiveProfile"

    static func load() -> (profiles: [Profile], activeId: UUID)? {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let profiles = try? JSONDecoder().decode([Profile].self, from: data),
              !profiles.isEmpty else { return nil }
        let stored = UserDefaults.standard.string(forKey: activeKey).flatMap(UUID.init)
        let activeId = profiles.contains { $0.id == stored } ? stored! : profiles[0].id
        return (profiles, activeId)
    }

    static func save(profiles: [Profile], activeId: UUID) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        UserDefaults.standard.set(activeId.uuidString, forKey: activeKey)
    }
}
