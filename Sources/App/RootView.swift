import SwiftUI

struct RootView: View {
    @State private var showingSettings = false
    @ObservedObject var session = VoiceSession.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                // Fundo com degradê suave e moderno
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    // Status de Conexão do Agente
                    HStack(spacing: 8) {
                        Circle()
                            .fill(connectionColor)
                            .frame(width: 10, height: 10)
                        Text(session.connectionState.rawValue)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(20)
                    
                    Spacer()
                    
                    // Estado Atual da Conversa
                    VStack(spacing: 16) {
                        Text(session.isCallActive ? "Conversa Ativa" : "Sem Chamada")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(session.sessionState.rawValue)
                            .font(.headline)
                            .foregroundColor(stateColor)
                            .animation(.easeInOut, value: session.sessionState)
                        
                        if !session.currentTranscript.isEmpty {
                            Text("\"\(session.currentTranscript)\"")
                                .font(.body)
                                .italic()
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                                .transition(.opacity)
                        }

                        // Transcrição da resposta do Hermes (streaming ao vivo)
                        if !session.hermesResponse.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Resposta do Hermes")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                ScrollView {
                                    Text(session.hermesResponse)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxHeight: 140)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal, 24)
                            .transition(.opacity)
                        }
                    }

                    // Botão Principal (Inicia / Encerra CallKit)
                    Button(action: {
                        if session.isCallActive {
                            session.endCall()
                        } else {
                            session.startCall()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(session.isCallActive ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                                .frame(width: 180, height: 180)
                                .scaleEffect(session.sessionState == .listening ? 1.08 : 1.0)
                                .animation(
                                    session.sessionState == .listening ?
                                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true) :
                                    .default,
                                    value: session.sessionState
                                )
                            
                            Circle()
                                .fill(session.isCallActive ? Color.red : Color.green)
                                .frame(width: 140, height: 140)
                                .shadow(color: (session.isCallActive ? Color.red : Color.green).opacity(0.3), radius: 15, x: 0, y: 8)
                            
                            Image(systemName: session.isCallActive ? "phone.down.fill" : "phone.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Botão Mudo/Unmute (funciona junto com os comandos do CallKit/CarPlay)
                    if session.isCallActive {
                        Button(action: {
                            session.toggleMute()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: session.isMuted ? "mic.slash.fill" : "mic.fill")
                                Text(session.isMuted ? "Mutado" : "Mudo")
                            }
                            .font(.headline)
                            .foregroundColor(session.isMuted ? .red : .primary)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    if !session.connectionLog.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Log do Agente:")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            
                            ScrollView {
                                Text(session.connectionLog)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.green)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                                    .padding(8)
                            }
                            .frame(height: 120)
                            .background(Color.black)
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        .transition(.opacity)
                    }
                    
                    Spacer()
                    
                    // Exibição da versão atual, data de build e commit (link p/ o GitHub)
                    VStack(spacing: 2) {
                        Text("v\(VersionManager.shared.currentVersionString) — \(VersionManager.shared.currentBuildDateString)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if let commitURL = VersionManager.shared.commitURL {
                            Link(destination: commitURL) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up.right.square")
                                    Text("commit \(VersionManager.shared.currentCommit)")
                                }
                                .font(.caption2)
                                .foregroundColor(.blue)
                            }
                        } else {
                            Text("commit \(VersionManager.shared.currentCommit)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .padding()
            }
            .navigationTitle("Hermes Voice")
            .navigationBarItems(trailing: Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
            })
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .hermesCarPlayActivate)) { _ in
                if !session.isCallActive {
                    session.startCall()
                }
            }
            .alert(item: Binding<AlertError?>(
                get: { session.errorMessage.map { AlertError(message: $0) } },
                set: { _ in session.errorMessage = nil }
            )) { error in
                Alert(
                    title: Text("Erro de Execução"),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    private var connectionColor: Color {
        switch session.connectionState {
        case .disconnected: return .red
        case .connecting: return .yellow
        case .connected: return .green
        }
    }
    
    private var stateColor: Color {
        switch session.sessionState {
        case .listening: return .blue
        case .speaking: return .green
        case .processing: return .orange
        case .idle: return .secondary
        }
    }
}

struct AlertError: Identifiable {
    let id = UUID()
    let message: String
}
