import Foundation

enum NativeSection: String, CaseIterable {
    case recipes, planner, shopping, profile
    var title: String { switch self { case .recipes: return "Recetas"; case .planner: return "Mi menú"; case .shopping: return "Compra"; case .profile: return "Perfil" } }
    var symbol: String { switch self { case .recipes: return "book"; case .planner: return "calendar"; case .shopping: return "basket"; case .profile: return "person.crop.circle" } }
}

struct NativeNavigationState {
    let section: NativeSection
    let visible: Bool
    let keepAwake: Bool
    init?(_ body: Any) {
        guard let data = body as? [String: Any], data["action"] as? String == "navigation",
              let raw = data["section"] as? String, let section = NativeSection(rawValue: raw),
              let visible = data["visible"] as? Bool, let keepAwake = data["keepAwake"] as? Bool else { return nil }
        self.section = section; self.visible = visible; self.keepAwake = keepAwake
    }
}
