import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var state: AppState

    var body: some View {
        HSplitView {
            previewArea
                .frame(minWidth: 400, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
            controls
                .frame(minWidth: 260, maxWidth: 320)
        }
        .toolbar {
            ToolbarItem {
                Button("Open Image…", systemImage: "photo.badge.plus") {
                    state.isImporterPresented = true
                }
            }
        }
        .fileImporter(
            isPresented: $state.isImporterPresented,
            allowedContentTypes: [.image]
        ) { result in
            if case .success(let url) = result {
                state.loadImage(from: url)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            state.loadImage(from: url)
            return true
        }
        .task {
            await state.pythonEnvironment.setUpIfNeeded()
        }
        .alert(
            "Couldn't Open Image",
            isPresented: Binding(
                get: { state.loadErrorMessage != nil },
                set: { if !$0 { state.loadErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.loadErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        Group {
            if let cgImage = displayedImage {
                Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else {
                ContentUnavailableView(
                    "No Image",
                    systemImage: "photo",
                    description: Text("Drop an image here or press ⌘O")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.05))
        .overlay(alignment: .topTrailing) {
            if state.isRenderingPreview {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = state.renderErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }

    /// Effect preview when one is selected and rendered; source image otherwise.
    private var displayedImage: CGImage? {
        if state.selectedEffect != nil, let preview = state.previewImage {
            return preview
        }
        return state.sourceImage
    }

    private var controls: some View {
        Form {
            Section("Effect") {
                Picker("Effect", selection: $state.selectedEffectID) {
                    Text("None").tag(String?.none)
                    ForEach(EffectCatalog.all, id: \.declaration.id) { effect in
                        Text(effect.declaration.name).tag(String?.some(effect.declaration.id))
                    }
                }
                .labelsHidden()
            }
            if let effect = state.selectedEffect {
                Section("Parameters") {
                    ParameterPanel(
                        parameters: effect.declaration.parameters,
                        values: parameterBinding
                    )
                }
            }
            if state.pythonEnvironment.status != .ready {
                Section("Python") {
                    pythonStatus
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: state.selectedEffectID) { _, newValue in
            state.ensureParameterValues(for: newValue)
            state.previewImage = nil
            state.schedulePreviewRender()
        }
        .onChange(of: state.parameterValues) {
            state.schedulePreviewRender()
        }
    }

    @ViewBuilder
    private var pythonStatus: some View {
        switch state.pythonEnvironment.status {
        case .checking, .ready:
            EmptyView()
        case .settingUp(let message):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var parameterBinding: Binding<[String: ParameterValue]> {
        Binding(
            get: { state.selectedEffectID.flatMap { state.parameterValues[$0] } ?? [:] },
            set: { if let id = state.selectedEffectID { state.parameterValues[id] = $0 } }
        )
    }
}

#Preview {
    ContentView(state: AppState())
}
