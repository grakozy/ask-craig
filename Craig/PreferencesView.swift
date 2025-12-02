import SwiftUI

struct PreferencesView: View {
    @State private var availableTriggers: [String] = ["/craig ", "/ask ", "/ai "]
    @State private var selectedTrigger: String = UserDefaults.standard.string(forKey: "CraigCurrentTrigger") ?? "/craig "

    @State private var models: [String] = []
    @State private var selectedModel: String = UserDefaults.standard.string(forKey: "CraigSelectedModel") ?? "llama3.2:1b-instruct-q4_K_M"

    @State private var temperature: Double = UserDefaults.standard.object(forKey: "CraigTemperature") as? Double ?? 0.2
    @State private var topP: Double = UserDefaults.standard.object(forKey: "CraigTopP") as? Double ?? 0.9
    @State private var maxTokens: Int = UserDefaults.standard.object(forKey: "CraigMaxTokens") as? Int ?? 256

    @State private var ollamaStatus: String = "Unknown"
    @State private var isCheckingStatus: Bool = false

    private let service = OllamaService()

    var body: some View {
        Form {
            Section("Trigger") {
                Picker("Trigger phrase", selection: $selectedTrigger) {
                    ForEach(availableTriggers, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: selectedTrigger) { newValue in
                    NotificationCenter.default.post(name: Notification.Name("CraigTriggerChanged"), object: nil, userInfo: ["trigger": newValue])
                }
                Text("Type the trigger followed by your question, then press Return.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Model") {
                HStack(spacing: 8) {
                    Picker("Ollama model", selection: $selectedModel) {
                        if models.isEmpty {
                            Text(selectedModel).tag(selectedModel)
                        } else {
                            ForEach(models, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Button("Refresh") { fetchModels() }
                        .disabled(isCheckingStatus)
                }
                .onChange(of: selectedModel) { newValue in
                    NotificationCenter.default.post(name: Notification.Name("CraigSelectedModelChanged"), object: nil, userInfo: ["model": newValue])
                }
                Text("Choose a small, fast model for the best responsiveness.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Generation") {
                HStack {
                    Text("Temperature")
                    Slider(value: $temperature, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", temperature)).frame(width: 48, alignment: .trailing)
                }
                .onChange(of: temperature) { _ in postGenOptions() }

                HStack {
                    Text("Top P")
                    Slider(value: $topP, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", topP)).frame(width: 48, alignment: .trailing)
                }
                .onChange(of: topP) { _ in postGenOptions() }

                HStack {
                    Text("Max tokens")
                    Stepper(value: $maxTokens, in: 32...8192, step: 32) {
                        Text("\(maxTokens)")
                    }
                }
                .onChange(of: maxTokens) { _ in postGenOptions() }
                Text("Controls response length and creativity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                HStack {
                    if isCheckingStatus { ProgressView().scaleEffect(0.8) }
                    Text("Ollama: \(ollamaStatus)")
                    Spacer()
                    Button("Check Ollama") { checkOllama() }
                }
                Button("Open Accessibility Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 520)
        .onAppear {
            fetchModels()
            checkOllama()
        }
    }

    private func postGenOptions() {
        NotificationCenter.default.post(name: Notification.Name("CraigGenOptionsChanged"), object: nil, userInfo: [
            "temperature": temperature,
            "topP": topP,
            "maxTokens": maxTokens
        ])
    }

    private func fetchModels() {
        isCheckingStatus = true
        service.listModels { result in
            DispatchQueue.main.async {
                self.isCheckingStatus = false
                switch result {
                case .success(let names):
                    self.models = names
                    // Ensure selected model is present or pick first
                    if !names.contains(self.selectedModel), let first = names.first {
                        self.selectedModel = first
                    }
                case .failure:
                    break
                }
            }
        }
    }

    private func checkOllama() {
        isCheckingStatus = true
        service.checkStatus { running in
            DispatchQueue.main.async {
                self.isCheckingStatus = false
                self.ollamaStatus = running ? "Running ✓" : "Not running ✗"
            }
        }
    }
}

#Preview {
    PreferencesView()
}
