import Foundation
import UserNotifications

actor DeviceTimers {
    private var revisions: [String: Int] = [:]
    func update(id: String, title: String, timers: [String: Any]) async throws {
        guard id.utf8.count <= 80, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }), title.utf8.count <= 1000, timers.count <= 100 else { throw LocalRecipeError.invalid("Temporizadores no válidos.") }
        let version = (revisions[id] ?? 0) + 1; revisions[id] = version
        let center = UNUserNotificationCenter.current(), prefix = "recetario.timer." + id + "."
        let existing = await center.pendingNotificationRequests()
        guard revisions[id] == version else { return }
        center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier))
        var pending: [(String, TimeInterval)] = []
        for (step, raw) in timers {
            guard let index = Int(step), index >= 0, index < 100, let timer = raw as? [String: Any], let deadline = timer["deadline"] as? Double else { throw LocalRecipeError.invalid("Temporizador no válido.") }
            let remaining = deadline / 1000 - Date().timeIntervalSince1970
            if remaining > 0 && remaining <= 86400 { pending.append((step, remaining)) }
        }
        guard !pending.isEmpty else { return }
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined { _ = try await center.requestAuthorization(options: [.alert, .sound]); settings = await center.notificationSettings() }
        guard revisions[id] == version, [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        for (step, remaining) in pending {
            guard revisions[id] == version else { return }
            let content = UNMutableNotificationContent(); content.title = "Temporizador terminado"
            content.body = title + " · Paso " + String((Int(step) ?? 0) + 1) + ". Comprueba el punto."
            content.sound = .default
            let identifier = prefix + String(version) + "." + step
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false)))
            if revisions[id] != version { center.removePendingNotificationRequests(withIdentifiers: [identifier]); return }
        }
    }
}
