import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @Environment(\.dismiss) var dismiss
    @State private var isPasswordVisible = false
    @State private var showingChangelog = false
    @State private var isTesting = false
    @State private var testResult: String? = nil
    @State private var testSucceeded = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Conexão do Hermes"),
                        footer: Text("URL base do API server (ex.: https://api.egger.app.br). A autenticação é via API Key (Bearer), definida por API_SERVER_KEY no servidor.")) {
                    TextField("URL da API", text: $settings.hostUrl)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    HStack {
                        if isPasswordVisible {
                            TextField("API Key (Bearer)", text: $settings.apiKey)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("API Key (Bearer)", text: $settings.apiKey)
                        }

                        Button(action: {
                            isPasswordVisible.toggle()
                        }) {
                            Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Button(action: testConnection) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                Text("Testando...")
                            } else {
                                Image(systemName: "bolt.horizontal.circle")
                                Text("Testar conexão")
                            }
                        }
                    }
                    .disabled(isTesting || settings.hostUrl.isEmpty)

                    if let testResult = testResult {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: testSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(testSucceeded ? .green : .red)
                            Text(testResult)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Section(header: Text("Configurações de Voz")) {
                    Picker("Idioma do Reconhecimento", selection: $settings.sttLanguage) {
                        Text("Português (Brasil)").tag("pt-BR")
                        Text("Inglês (EUA)").tag("en-US")
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Velocidade da Voz (TTS)")
                            Spacer()
                            Text(String(format: "%.1f", settings.ttsRate))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.ttsRate, in: 0.1...1.0, step: 0.05)
                    }
                }
                
                Section {
                    HStack {
                        Spacer()
                        Button(action: {
                            showingChangelog = true
                        }) {
                            VStack(spacing: 4) {
                                Text("Versão \(VersionManager.shared.currentVersionString)")
                                    .font(.footnote)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                Text("Compilado em: \(VersionManager.shared.currentBuildDateString)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Configurações")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Concluído") {
                dismiss()
            })
            .sheet(isPresented: $showingChangelog) {
                ChangelogView()
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                try await HermesAgentClient.shared.connect()

                // A falha em obter o modelo/motor não invalida o teste de conexão —
                // é uma informação extra de diagnóstico, não um requisito de saúde.
                var modelLine = ""
                if let info = try? await HermesAgentClient.shared.fetchModelInfo() {
                    modelLine = "\nModelo: \(info.model)\nMotor: \(info.provider)"
                }

                await MainActor.run {
                    testSucceeded = true
                    testResult = "Conectado ao API server com sucesso." + modelLine
                    isTesting = false
                }
                await HermesAgentClient.shared.disconnect()
            } catch {
                await MainActor.run {
                    testSucceeded = false
                    testResult = error.localizedDescription
                    isTesting = false
                }
            }
        }
    }
}

struct ChangelogView: View {
    @Environment(\.dismiss) var dismiss
    let history = VersionManager.shared.history
    
    var body: some View {
        NavigationView {
            List {
                ForEach(history) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Versão \(entry.version)")
                                .font(.headline)
                                .fontWeight(.bold)
                            
                            Text("Build \(entry.build)")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .cornerRadius(4)
                            
                            Spacer()
                            
                            if entry.isCurrent {
                                Text("Atual")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .cornerRadius(10)
                            }
                        }
                        
                        Text(entry.isCurrent ? "Compilado em: \(VersionManager.shared.currentBuildDateString)" : "Lançado em: \(entry.date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(entry.changes, id: \.self) { change in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundColor(.blue)
                                    Text(change)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Histórico de Versões")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Fechar") {
                dismiss()
            })
        }
    }
}
