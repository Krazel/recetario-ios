import UIKit
import PhotosUI
import UniformTypeIdentifiers

@MainActor final class LocalRecipeEditor: UIViewController, PHPickerViewControllerDelegate {
    private var recipe: LocalRecipe
    private let original: LocalRecipe
    private let store: LocalRecipeStore
    private let save: (LocalRecipe) throws -> Void
    private let name = UITextField(), source = UITextField(), collection = UITextField()
    private let ingredients = UITextView(), steps = UITextView(), notes = UITextView()
    private let photoView = UIImageView(), photoStatus = UILabel()
    private var pendingPhoto: Data?, removePhoto = false, photoRequest = UUID()
    private var loadingPhoto = false, closed = false

    init(recipe: LocalRecipe, store: LocalRecipeStore, save: @escaping (LocalRecipe) throws -> Void) {
        self.recipe = recipe; self.original = recipe; self.store = store; self.save = save
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = recipe.title.isEmpty ? "Nueva receta" : "Editar receta"
        view.backgroundColor = LocalRecipeStyle.background
        navigationController?.navigationBar.tintColor = LocalRecipeStyle.accent
        isModalInPresentation = true
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive; view.addSubview(scroll)
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20)
        ])
        func heading(_ text: String) {
            let label = UILabel(); label.text = text; label.font = .preferredFont(forTextStyle: .headline)
            label.adjustsFontForContentSizeCategory = true; stack.addArrangedSubview(label)
        }
        heading("Nombre")
        name.text = recipe.title; name.placeholder = "Nombre de la receta"; name.accessibilityLabel = "Nombre de la receta"
        name.borderStyle = .roundedRect; name.font = .preferredFont(forTextStyle: .body)
        name.adjustsFontForContentSizeCategory = true; name.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        stack.addArrangedSubview(name)
        heading("Foto")
        photoView.contentMode = .scaleAspectFit; photoView.clipsToBounds = true
        photoView.heightAnchor.constraint(equalToConstant: 200).isActive = true
        photoView.isAccessibilityElement = true; photoView.accessibilityLabel = "Foto de la receta"
        if let id = recipe.photoID, let data = try? store.photoData(id) { photoView.image = UIImage(data: data) }
        photoView.isHidden = photoView.image == nil; stack.addArrangedSubview(photoView)
        let choose = UIButton(type: .system); choose.setTitle("Elegir foto", for: .normal)
        choose.addTarget(self, action: #selector(choosePhoto), for: .touchUpInside); stack.addArrangedSubview(choose)
        let remove = UIButton(type: .system); remove.setTitle("Quitar foto", for: .normal)
        remove.addTarget(self, action: #selector(clearPhoto), for: .touchUpInside); stack.addArrangedSubview(remove)
        photoStatus.font = .preferredFont(forTextStyle: .footnote); photoStatus.numberOfLines = 0
        photoStatus.textColor = .secondaryLabel; stack.addArrangedSubview(photoStatus)
        for (label, field, value) in [("Ingredientes", ingredients, recipe.ingredients), ("Preparación", steps, recipe.steps), ("Notas", notes, recipe.notes)] {
            heading(label); field.text = value; field.accessibilityLabel = label
            field.font = .preferredFont(forTextStyle: .body); field.adjustsFontForContentSizeCategory = true
            field.backgroundColor = .secondarySystemGroupedBackground
            field.layer.cornerRadius = 10; field.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true; stack.addArrangedSubview(field)
        }
        heading("Recetario")
        collection.text = recipe.collection; collection.placeholder = "Por ejemplo, cenas"
        collection.accessibilityLabel = "Recetario"; collection.borderStyle = .roundedRect
        collection.font = .preferredFont(forTextStyle: .body); collection.adjustsFontForContentSizeCategory = true
        collection.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true; stack.addArrangedSubview(collection)
        heading("Enlace de origen (opcional)")
        source.text = recipe.sourceURL; source.placeholder = "https://…"; source.keyboardType = .URL
        source.accessibilityLabel = "Enlace de origen"; source.autocapitalizationType = .none; source.autocorrectionType = .no
        source.borderStyle = .roundedRect; source.font = .preferredFont(forTextStyle: .body)
        source.adjustsFontForContentSizeCategory = true; source.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        stack.addArrangedSubview(source)
        let sourceNote = UILabel(); sourceNote.numberOfLines = 0; sourceNote.font = .preferredFont(forTextStyle: .footnote)
        sourceNote.adjustsFontForContentSizeCategory = true; sourceNote.textColor = .secondaryLabel
        sourceNote.text = "El enlace se conserva como referencia. Esta pantalla no extrae una receta automáticamente."
        stack.addArrangedSubview(sourceNote)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancelar", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Guardar", style: .done, target: self, action: #selector(commit))
    }
    private func currentDraft() -> LocalRecipe {
        var value = recipe
        value.title = (name.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        value.ingredients = ingredients.text; value.steps = steps.text; value.notes = notes.text
        let url = (source.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        value.sourceURL = url.isEmpty ? nil : url
        let group = (collection.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        value.collection = group.isEmpty ? nil : group
        if removePhoto { value.photoID = nil }
        return value
    }
    @objc private func cancel() {
        if !loadingPhoto && pendingPhoto == nil && currentDraft().matches(original) { close(); return }
        let alert = UIAlertController(title: "¿Descartar el borrador?", message: "Los cambios que no hayas guardado se perderán.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Seguir editando", style: .cancel))
        alert.addAction(UIAlertAction(title: "Descartar", style: .destructive) { [weak self] _ in self?.close() })
        present(alert, animated: true)
    }
    private func close() { closed = true; photoRequest = UUID(); dismiss(animated: true) }
    @objc private func commit() {
        guard !loadingPhoto else { return }
        var value = currentDraft()
        do {
            try LocalRecipeStore.validate(value)
            if let pendingPhoto { value.photoID = try store.savePhoto(pendingPhoto) }
            try save(value)
            close()
        } catch { showError(error.localizedDescription) }
    }
    @objc private func choosePhoto() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images; configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration); picker.delegate = self
        present(picker, animated: true)
    }
    @objc private func clearPhoto() {
        photoRequest = UUID(); loadingPhoto = false; navigationItem.rightBarButtonItem?.isEnabled = true
        pendingPhoto = nil; removePhoto = true; photoView.image = nil; photoView.isHidden = true; photoStatus.text = nil
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true) { [weak self] in self?.loadSelection(results) }
    }
    private func loadSelection(_ results: [PHPickerResult]) {
        guard let result = results.first else { return }
        let request = UUID(); photoRequest = request
        loadingPhoto = true; navigationItem.rightBarButtonItem?.isEnabled = false; photoStatus.text = "Preparando foto…"
        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
            let outcome: Result<Data, Error>
            do {
                guard let url else { throw error ?? LocalRecipeError.invalid("No se pudo abrir la foto.") }
                // Provider URL is temporary: consume it inside this callback.
                outcome = .success(try LocalRecipePhoto.compressedFile(at: url))
            } catch { outcome = .failure(error) }
            Task { @MainActor [weak self] in
                guard let self, !self.closed, self.photoRequest == request else { return }
                self.loadingPhoto = false; self.navigationItem.rightBarButtonItem?.isEnabled = true
                self.photoStatus.text = nil
                switch outcome {
                case .success(let data):
                    self.pendingPhoto = data; self.removePhoto = false
                    self.photoView.image = UIImage(data: data); self.photoView.isHidden = false
                    self.photoStatus.text = "La foto se guardará en este dispositivo."
                case .failure(let error): self.showError(error.localizedDescription)
                }
            }
        }
    }
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "No se ha guardado", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Volver", style: .default)); present(alert, animated: true)
    }
}
