import Foundation

enum ZoomPreferences {
    private static let key = "GoatZoomLevels"

    static func zoom(forHost host: String) -> Double? {
        let map = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        return map[host]
    }

    static func set(zoom: Double, forHost host: String) {
        var map = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        if zoom == 0 {
            map.removeValue(forKey: host)
        } else {
            map[host] = zoom
        }
        UserDefaults.standard.set(map, forKey: key)
    }
}
