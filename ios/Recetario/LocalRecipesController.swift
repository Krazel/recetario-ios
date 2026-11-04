import UIKit
import UniformTypeIdentifiers

@MainActor final class LocalRecipesController: UITableViewController, UISearchResultsUpdating, UIDocumentPickerDelegate {
    private let store: LocalRecipeStore
    private var items: [LocalRecipe] = []
    private let search = UISearchController(searchResultsController: nil)
    private var collection: String?
    private var favoritesOnly = false
    private let notice = UILabel()

    init(store: LocalRecipeStore) { self.store = store; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Mis recetas"
        view.backgroundColor = LocalRecipeStyle.background
        navigationController?.navigationBar.tintColor = LocalRecipeStyle.accent
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add))
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Buscar recetas o ingredientes"
        navigationItem.searchController = search
        definesPresentationContext = true
        notice.numberOfLines = 0
        notice.font = .preferredFont(forTextStyle: .subheadline)
        notice.adjustsFontForContentSizeCategory = true
        notice.textColor = .secondaryLabel
        notice.textAlignment = .center
        notice.text = "Guardado en este dispositivo\nRecetas y fotos disponibles sin conexión."
        tableView.tableHeaderView = notice
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        navigationController?.isToolbarHidden = false
        render()
        // No AccountClient, WebKit, identity request, foreground observer or sync task.
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); render() }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let height = notice.sizeThatFits(CGSize(width: max(100, tableView.bounds.width - 40), height: .greatestFiniteMagnitude)).height + 32
        if notice.frame.height != height { notice.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: height); tableView.tableHeaderView = notice }
    }
    func updateSearchResults(for searchController: UISearchController) { render() }
    private func render() {
        guard isViewLoaded else { return }
        let query = (search.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        items = store.visible.filter { recipe in
            (!favoritesOnly || recipe.favorite == true) &&
            (collection == nil || (recipe.collection ?? "") == collection) &&
            (query.isEmpty || [recipe.title, recipe.ingredients, recipe.notes].contains { $0.localizedStandardContains(query) })
        }
        tableView.reloadData()
        var actions = [UIAction(title: "Todos los recetarios", state: collection == nil ? .on : .off) { [weak self] _ in self?.collection = nil; self?.render() }]
        let names = Set(store.visible.compactMap(\.collection).filter { !$0.isEmpty }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for name in names {
            actions.append(UIAction(title: name, state: collection == name ? .on : .off) { [weak self] _ in self?.collection = name; self?.render() })
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: collection ?? "Recetarios", menu: UIMenu(children: actions))
        let favorite = UIBarButtonItem(image: UIImage(systemName: favoritesOnly ? "star.fill" : "star"), style: .plain, target: self, action: #selector(toggleFavorites))
        favorite.accessibilityLabel = favoritesOnly ? "Mostrar todas las recetas" : "Mostrar favoritas"
        let copies = UIBarButtonItem(title: "Copias", menu: UIMenu(children: [
            UIAction(title: "Exportar recetas y fotos", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.exportCopy() },
            UIAction(title: "Importar una copia", image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in self?.importCopy() },
            UIAction(title: "Cómo guardar una copia", image: UIImage(systemName: "info.circle")) { [weak self] _ in
                self?.inform("Tus recetas están en este dispositivo", "Exporta una copia y guárdala en Archivos o donde prefieras. Incluye las fotos. Puedes importarla en otro iPhone. Borrar la app puede borrar sus datos locales; crear una copia te permite recuperarlos. La app no envía esta copia a nuestros servidores.")
            }
        ]))
        toolbarItems = [favorite, UIBarButtonItem(systemItem: .flexibleSpace), copies]
        if items.isEmpty {
            let empty = UILabel()
            empty.text = store.visible.isEmpty ? "Tu recetario empieza aquí\nPulsa + para añadir una receta\no importa una copia desde Copias." : "No hay recetas con este filtro."
            empty.numberOfLines = 0; empty.textAlignment = .center; empty.textColor = .secondaryLabel
            empty.font = .preferredFont(forTextStyle: .body); empty.adjustsFontForContentSizeCategory = true
            tableView.backgroundView = empty
        } else { tableView.backgroundView = nil }
    }
    @objc private func toggleFavorites() { favoritesOnly.toggle(); render() }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil), recipe = items[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = recipe.title; content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.textProperties.numberOfLines = 2
        content.secondaryText = [recipe.favorite == true ? "Favorita" : "", recipe.collection ?? "", recipe.ingredients].filter { !$0.isEmpty }.joined(separator: " · ")
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        content.secondaryTextProperties.numberOfLines = 2
        if let id = recipe.photoID, let bytes = try? store.photoData(id) { content.image = UIImage(data: bytes) }
        else { content.image = UIImage(systemName: "fork.knife") }
        content.imageProperties.maximumSize = CGSize(width: 64, height: 64)
        content.imageProperties.cornerRadius = 10
        cell.contentConfiguration = content
        cell.tintColor = LocalRecipeStyle.accent
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.pushViewController(LocalRecipeDetailController(id: items[indexPath.row].id, store: store), animated: true)
    }
    @objc private func add() { presentEditor(LocalRecipe(id: UUID().uuidString.lowercased(), title: "")) }
    private func presentEditor(_ recipe: LocalRecipe) {
        let scope = store.state.active
        let editor = LocalRecipeEditor(recipe: recipe, store: store) { [weak self] value in
            guard let self else { return }
            try self.store.save(value, expectedScope: scope)
            self.render()
        }
        present(UINavigationController(rootViewController: editor), animated: true)
    }
    func openImportSource(_ url: URL) {
        guard ["https", "http"].contains(url.scheme ?? ""), url.host != nil, url.user == nil, url.password == nil else { return }
        if presentedViewController != nil {
            inform("Hay un borrador abierto", "Termina de guardarlo antes de abrir otra receta. El enlace no se ha importado.")
            return
        }
        var recipe = LocalRecipe(id: UUID().uuidString.lowercased(), title: "")
        recipe.sourceURL = url.absoluteString
        presentEditor(recipe)
    }
    private func exportCopy() {
        do {
            let data = try store.makeBackup()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Recetario-copia.json")
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.popoverPresentationController?.barButtonItem = toolbarItems?.last
            share.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: directory) }
            present(share, animated: true)
        } catch { inform("No se pudo exportar la copia", error.localizedDescription) }
    }
    private func importCopy() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.delegate = self; picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard size.isRegularFile == true, let count = size.fileSize, count <= LocalRecipeStore.maximumBackupBytes else { throw LocalRecipeError.invalid("La copia supera el tamaño admitido o no es un archivo.") }
            let preview = try store.previewBackup(Data(contentsOf: url))
            let alert = UIAlertController(title: "Importar \(preview.count) recetas", message: "Se añadirán a este dispositivo con sus fotos. Conservaremos las recetas actuales y omitiremos las copias idénticas.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
            alert.addAction(UIAlertAction(title: "Importar", style: .default) { [weak self] _ in
                guard let self else { return }
                do { let count = try self.store.restore(preview); self.render(); self.inform("Copia importada", "\(count) recetas añadidas. Las recetas que ya estaban guardadas se han conservado.") }
                catch { self.inform("No se ha importado la copia", error.localizedDescription) }
            })
            present(alert, animated: true)
        } catch { inform("No se pudo abrir la copia", error.localizedDescription) }
    }
    private func inform(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default))
        (presentedViewController ?? self).present(alert, animated: true)
    }
}

enum LocalRecipeStyle {
    static let background = UIColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1)
    static let accent = UIColor(red: 0.73, green: 0.17, blue: 0.15, alpha: 1)
}
