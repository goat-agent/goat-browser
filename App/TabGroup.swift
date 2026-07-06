import Foundation
import Observation

@MainActor
@Observable
final class TabGroup: Identifiable {
    let id: UUID
    var name: String
    var colorIndex: Int
    var isCollapsed: Bool = false

    init(id: UUID = UUID(), name: String = "", colorIndex: Int) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
    }

    var displayName: String { name.isEmpty ? "Group" : name }
}
