import UIKit

@MainActor final class LocalRecipeDetailController: UIViewController {
    private let id: String, store: LocalRecipeStore
    private let scroll = UIScrollView(), stack = UIStackView()
    init(id: String, store: LocalRecipeStore) { self.id = id; self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = LocalRecipeStyle.background
        scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20)
        ])
        render()
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); if isViewLoaded { render() } }
    private func label(_ text: String, style: UIFont.TextStyle = .body) {
        let label = UILabel(); label.text = text; label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: style); label.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(label)
    }
    private func render() {
        for child in stack.arrangedSubviews { stack.removeArrangedSubview(child); child.removeFromSuperview() }
        guard let recipe = store.records[id], !recipe.deleted else { label("Esta receta ya no está disponible."); navigationItem.rightBarButtonItems = nil; return }
        title = recipe.title
        label(recipe.title, style: .largeTitle)
        if let group = recipe.collection, !group.isEmpty { label(group, style: .subheadline) }
        if let photo = recipe.photoID {
            if let data = try? store.photoData(photo), let image = UIImage(data: data) {
                let view = UIImageView(image: image); view.contentMode = .scaleAspectFit
                view.heightAnchor.constraint(equalToConstant: 240).isActive = true
                view.isAccessibilityElement = true; view.accessibilityLabel = "Foto de \(recipe.title)"
                stack.addArrangedSubview(view)
            } else { label("No se ha podido abrir la foto. El resto de la receta se conserva.", style: .footnote) }
        }
        for (heading, body) in [("Ingredientes", recipe.ingredients), ("Preparación", recipe.steps), ("Notas", recipe.notes)] where !body.isEmpty {
            label(heading, style: .title2); label(body)
        }
        if let source = recipe.sourceURL, !source.isEmpty {
            let button = UIButton(type: .system); button.setTitle("Abrir enlace de origen", for: .normal)
            button.addAction(UIAction { _ in if let url = URL(string: source) { UIApplication.shared.open(url) } }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        let favorite = UIBarButtonItem(image: UIImage(systemName: recipe.favorite == true ? "star.fill" : "star"), style: .plain, target: self, action: #selector(toggleFavorite))
        favorite.accessibilityLabel = recipe.favorite == true ? "Quitar de favoritas" : "Añadir a favoritas"
        let edit = UIBarButtonItem(title: "Editar", style: .plain, target: self, action: #selector(editRecipe))
        navigationItem.rightBarButtonItems = [edit, favorite]
        let remove = UIButton(type: .system); remove.setTitle("Eliminar receta", for: .normal); remove.tintColor = .systemRed
        remove.addTarget(self, action: #selector(deleteRecipe), for: .touchUpInside); stack.addArrangedSubview(remove)
    }
    @objc private func editRecipe() {
        guard let recipe = store.records[id] else { return }
        let scope = store.state.active
        let editor = LocalRecipeEditor(recipe: recipe, store: store) { [weak self] value in
            guard let self else { return }; try self.store.save(value, expectedScope: scope); self.render()
        }
        present(UINavigationController(rootViewController: editor), animated: true)
    }
    @objc private func toggleFavorite() {
        guard var recipe = store.records[id] else { return }
        recipe.favorite = !(recipe.favorite ?? false)
        do { try store.save(recipe); render() } catch { showError(error.localizedDescription) }
    }
    @objc private func deleteRecipe() {
        guard let recipe = store.records[id] else { return }
        let alert = UIAlertController(title: "¿Eliminar esta receta?", message: "Si tienes una copia exportada, podrás volver a importarla.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Eliminar", style: .destructive) { [weak self] _ in
            guard let self else { return }
            do { try self.store.delete(recipe); self.navigationController?.popViewController(animated: true) }
            catch { self.showError(error.localizedDescription) }
        }); present(alert, animated: true)
    }
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "No se pudo guardar el cambio", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default)); present(alert, animated: true)
    }
}
