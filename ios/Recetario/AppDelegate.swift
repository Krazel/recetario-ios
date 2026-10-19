import UIKit

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var root: RecetarioController?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let controller = RecetarioController()
        root = controller
        if let url = launchOptions?[.url] as? URL, let target = NavigationPolicy.importURL(url) { controller.open(target) }
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let target = NavigationPolicy.importURL(url) else { return false }
        root?.open(target)
        return true
    }
}
