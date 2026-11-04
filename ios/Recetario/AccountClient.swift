import UIKit
import WebKit

// Uses the SAME Site and the SAME WKWebView cookie store as the online app.
// No gateway, alternate identity, shared bypass token or new authentication service.
@MainActor final class AccountClient {
    enum Failure: Error, LocalizedError {
        case expired, server(String), http(Int,String)
        var errorDescription: String? {
            switch self { case .expired: return "Entra en tu cuenta online para continuar con el guardado automático."
            case .server(let text), .http(_,let text): return text }
        }
    }
    private var online: RecetarioController?
    var boundAccountId: String?
    var site: RecetarioController {
        if let online { return online }
        let value=RecetarioController(); online=value; return value
    }
    func api(_ path: String, method: String = "GET", body: [String:Any]? = nil) async throws -> [String:Any] {
        let target: String
        switch path { case "api/me": target="/api/account"
        case "api/sync": target="/api/mobile-sync"
        case "api/ai/budget": target="/api/ai-budget"
        case "api/account/logout": target="/api/account/auth"
        default: throw Failure.server("Operación de cuenta no permitida.") }
        let controller=site; controller.loadViewIfNeeded()
        guard NavigationPolicy.isTrusted(controller.webView.url) else { throw Failure.expired }
        // Fixed same-origin paths only. Arguments are structured, never JS interpolation.
        let value = try await controller.webView.callAsyncJavaScript("""
            if(location.origin!==origin)throw new Error('La sesión ha cambiado de origen.');
            const r=await fetch(path,{method,credentials:'same-origin',cache:'no-store',
              headers:method==='GET'?{}:{'Content-Type':'application/json'},
              ...(method==='GET'?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(20000)});
            const data=await r.json();return {status:r.status,data};
            """, arguments:["origin":NavigationPolicy.origin.absoluteString,"path":target,"method":method,"body":body ?? [:]], in:nil, contentWorld:.defaultClient)
        guard let reply=value as? [String:Any],let status=reply["status"] as? Int,let data=reply["data"] as? [String:Any] else { throw Failure.server("No se pudo leer la respuesta. Tus cambios locales se conservan.") }
        if status==401 { throw Failure.expired }
        guard (200..<300).contains(status) else { throw Failure.http(status,data["error"] as? String ?? "No se completó el guardado online.") }
        return data
    }
    func logout() async throws {
        guard let expected=boundAccountId else { throw Failure.expired }
        let current=try await api("api/me")
        guard (current["user"] as? [String:Any])?["id"] as? String == expected else { throw Failure.server("Hay otra cuenta abierta. No se ha cerrado esa sesión.") }
        _ = try await api("api/account/logout",method:"POST",body:["action":"logout","expectedAccountId":expected])
        site.open(NavigationPolicy.origin)
        boundAccountId=nil
        // Only the Recetario session ends. The outer Sites access remains intact.
    }
}

@MainActor final class AccountsController: UIViewController {
    private let client: AccountClient
    private let onAuthenticated: () async throws -> Void
    private var finishing=false, completed=false
    init(client: AccountClient,onAuthenticated: @escaping () async throws -> Void){self.client=client;self.onAuthenticated=onAuthenticated;super.init(nibName:nil,bundle:nil)}
    required init?(coder:NSCoder){fatalError("init(coder:) is unavailable")}
    override func viewDidLoad(){
        super.viewDidLoad();title="Cuenta online"
        navigationItem.leftBarButtonItem=UIBarButtonItem(title:"Mis recetas locales",style:.plain,target:self,action:#selector(close))
        let web=client.site
        web.willMove(toParent:nil);web.view.removeFromSuperview();web.removeFromParent()
        addChild(web);web.view.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(web.view)
        NSLayoutConstraint.activate([web.view.topAnchor.constraint(equalTo:view.topAnchor),web.view.bottomAnchor.constraint(equalTo:view.bottomAnchor),web.view.leadingAnchor.constraint(equalTo:view.leadingAnchor),web.view.trailingAnchor.constraint(equalTo:view.trailingAnchor)])
        web.didMove(toParent:self)
        web.onDocumentReady={ [weak self] in self?.checkAccount() }
    }
    override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated);checkAccount()}
    private func checkAccount(){
        guard !finishing,!completed else{return};finishing=true
        Task{defer{finishing=false}
            do{_ = try await client.api("api/me");try await onAuthenticated();completed=true}
            catch AccountClient.Failure.expired{} // The Site presents its actual sign-in flow.
            catch{let alert=UIAlertController(title:"Guardado pendiente",message:error.localizedDescription,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"Continuar",style:.default));if presentedViewController == nil{present(alert,animated:true)}}
        }
    }
    @objc private func close(){client.site.onDocumentReady=nil;dismiss(animated:true)}
}
