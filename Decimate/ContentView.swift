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
            if let cgImage = state.sourceImage {
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
        }
        .formStyle(.grouped)
        .onChange(of: state.selectedEffectID) { _, newValue in
            state.ensureParameterValues(for: newValue)
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
