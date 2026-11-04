import UIKit

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var root: OfflineAppController?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        do {
            let controller=try OfflineAppController(database: DeviceDatabase())
            root=controller;window.rootViewController=controller
        } catch {
            let failed=UIViewController();failed.view.backgroundColor = .systemBackground
            let label=UILabel();label.numberOfLines=0;label.text="No se puede abrir el recetario local. No borres la app ni sus datos. Reintenta con el dispositivo desbloqueado.\n\(error.localizedDescription)";label.translatesAutoresizingMaskIntoConstraints=false;failed.view.addSubview(label)
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:failed.view.leadingAnchor,constant:24),label.trailingAnchor.constraint(equalTo:failed.view.trailingAnchor,constant:-24),label.centerYAnchor.constraint(equalTo:failed.view.centerYAnchor)])
            window.rootViewController=failed
        }
        window.makeKeyAndVisible()
        self.window = window
        if let url=launchOptions?[.url] as? URL,let source=NavigationPolicy.importSourceURL(url){DispatchQueue.main.async{[weak self] in self?.root?.openImportSource(source)}}
        return true
    }
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let source = NavigationPolicy.importSourceURL(url) else { return false }
        root?.openImportSource(source)
        return true
    }
}
