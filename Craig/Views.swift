import SwiftUI
import Combine
import AppKit

// MARK: - Modal View
struct CraigModalView: View {
    let question: String
    let ollamaService: OllamaService
    let onInsert: (String) -> Void
    let onClose: () -> Void

    @State private var response: String = ""
    @State private var isLoading: Bool = true
    @State private var error: String? = nil
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles").foregroundColor(.purple)
                Text("Craig").font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Text("Esc to close").font(.caption).foregroundColor(.secondary)
                    Button(action: { onClose() }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                        .buttonStyle(.plain)
                        .help("Close")
                        .keyboardShortcut(.escape, modifiers: [])
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding()
            .background(Color.purple.opacity(0.1))

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your question:").font(.caption).foregroundColor(.secondary)
                    Text(question)
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("Response:").font(.caption).foregroundColor(.secondary)
                    if isLoading {
                        HStack { ProgressView().scaleEffect(0.8); Text("Craig is thinking...").foregroundColor(.secondary) }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else if let error = error {
                        Text(error).foregroundColor(.red).padding()
                    } else {
                        Text(response)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }

            // Buttons
            if !isLoading && error == nil {
                HStack(spacing: 12) {
                    Button(action: { onInsert(response) }) {
                        Text("Insert ↵").frame(maxWidth: .infinity).padding().background(Color.purple).foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])

                    Button(action: { let pb = NSPasteboard.general; pb.clearContents(); pb.setString(response, forType: .string) }) {
                        Text("Copy").frame(maxWidth: .infinity).padding().background(Color.white.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }

            Button(action: { onClose() }) { EmptyView() }.keyboardShortcut(.cancelAction).hidden()
        }
        .frame(width: 500, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .scaleEffect(appear ? 1 : 0.98)
        .opacity(appear ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: appear)
        .onAppear { appear = true; fetchResponse() }
        .onExitCommand(perform: { onClose() })
    }

    func fetchResponse() {
        ollamaService.ask(question: question) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let text): response = text
                case .failure(let err): error = "Error: \(err.localizedDescription)\n\nMake sure Ollama is running:\n1. Open Terminal\n2. Run: ollama serve"
                }
            }
        }
    }
}

// MARK: - Command HUD View
struct CommandHUDView: View {
    let trigger: String
    let preview: String
    @State private var appear = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.purple)
            Text(trigger).font(.caption).bold().foregroundStyle(.purple)
            Text(preview.isEmpty ? "" : preview).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 6)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : -4)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appear)
        .onAppear { appear = true }
    }
}

// MARK: - LiveCommandModel
final class LiveCommandModel: ObservableObject {
    @Published var question: String = ""
    @Published var submitTick: Int = 0
    @Published var lastResponse: String = ""
    @Published var lastError: String? = nil
}

// MARK: - CraigLiveModalView
struct CraigLiveModalView: View {
    let ollamaService: OllamaService
    @ObservedObject var model: LiveCommandModel
    let onInsert: (String) -> Void
    let onClose: () -> Void

    @State private var response: String = ""
    @State private var isLoading: Bool = false
    @State private var error: String? = nil
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles").foregroundColor(.purple)
                Text("Craig").font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Text("Esc to close").font(.caption).foregroundColor(.secondary)
                    Button(action: { onClose() }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color.purple.opacity(0.1))

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !model.question.isEmpty {
                            HStack { Spacer(minLength: 40); Text(model.question).padding(10).background(Color.accentColor.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 12)) }
                                .id("user")
                        } else {
                            HStack { Spacer(minLength: 40); Text("Start typing…").foregroundColor(.secondary).padding(10).background(Color.accentColor.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12)) }
                                .id("user")
                        }

                        if isLoading {
                            HStack(alignment: .top) { Text(""); VStack(alignment: .leading) { HStack { ProgressView().scaleEffect(0.8); Text("Craig is thinking…").foregroundColor(.secondary) } }; Spacer() }
                                .id("assistant")
                        } else if let error = error {
                            HStack(alignment: .top) { Text(""); VStack(alignment: .leading) { Text(error).foregroundColor(.red).padding(10).background(Color.red.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12)) }; Spacer() }
                                .id("assistant")
                        } else if !response.isEmpty {
                            HStack(alignment: .top) { Text(""); VStack(alignment: .leading) { Text(response).padding(10).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 12)) }; Spacer() }
                                .id("assistant")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .onChange(of: response) { _ in withAnimation { proxy.scrollTo("assistant", anchor: .bottom) } }
                .onChange(of: isLoading) { _ in withAnimation { proxy.scrollTo("assistant", anchor: .bottom) } }
                .onChange(of: model.question) { _ in withAnimation { proxy.scrollTo("user", anchor: .bottom) } }
            }

            HStack(spacing: 12) {
                Button(action: { onInsert(response) }) {
                    Text("Insert ↵")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background((!isLoading && error == nil && !response.isEmpty) ? Color.purple : Color.gray.opacity(0.4))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(isLoading || !(error == nil && !response.isEmpty))

                Button(action: { let pb = NSPasteboard.general; pb.clearContents(); pb.setString(response, forType: .string) }) {
                    Text("Copy").frame(maxWidth: .infinity).padding().background(Color.white.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(response.isEmpty)
            }
            .padding()
        }
        .frame(width: 560, height: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .scaleEffect(appear ? 1 : 0.98)
        .opacity(appear ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: appear)
        .onChange(of: model.submitTick) { _ in submit() }
        .onAppear { appear = true }
    }

    func submit() {
        let q = model.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true; response = ""; error = nil
        ollamaService.askStream(question: q, onToken: { token in
            DispatchQueue.main.async { self.response += token }
        }, onError: { err in
            DispatchQueue.main.async {
                self.isLoading = false
                let msg = "Error: \(err.localizedDescription)\n\nMake sure Ollama is running:\n1. Open Terminal\n2. Run: ollama serve"
                self.error = msg; self.model.lastError = msg
            }
        }, onComplete: {
            DispatchQueue.main.async { self.isLoading = false; self.model.lastResponse = self.response; self.model.lastError = nil }
        })
    }
}

