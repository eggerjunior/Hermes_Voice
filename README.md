# Hermes Voice 🎙️

Aplicativo iOS nativo escrito em **Swift + SwiftUI** que permite conversar por voz com o agente self-hosted **Hermes** via WebSocket (WSS) com Basic Auth. 

A conversa é modelada como uma **ligação virtual via CallKit**. Isso permite que, ao conectar o iPhone ao carro, o **CarPlay exiba automaticamente a interface nativa de chamadas**, roteando microfone e alto-falantes pelo sistema do veículo sem precisar de entitlements restritos de CarPlay ou aprovação da Apple.

---

## 🚀 Como Executar o Projeto (Do Zero ao iPhone)

### 1. Pré-requisitos instalados
As ferramentas de compilação automática já foram instaladas no seu ambiente:
- **XcodeGen:** Para gerar a estrutura do projeto `.xcodeproj`.
- **xcbeautify & swiftlint:** Para compilação e qualidade de código.

### 2. Configurando o seu Apple Developer Account (AÇÃO MINHA)
Como o app precisa ser executado em um **iPhone real** para usar o CallKit e testar o áudio do microfone/CarPlay, siga estes passos manuais:

1. Abra o Xcode.
2. Vá em **Xcode → Settings → Accounts** (ou `Cmd + ,` e selecione *Accounts*).
3. Clique no botão `+` no canto inferior esquerdo e adicione o seu **Apple ID**.
4. Depois de logado, selecione a sua conta e você verá o seu **Team Name** e o **Team ID** associado.
5. Copie o seu **Team ID** (ele é composto por 10 caracteres alfanuméricos).
6. Abra o arquivo [project.yml](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/project.yml) no seu editor e insira o seu Team ID descomentando a chave correspondente:
   ```yaml
   settings:
     base:
       ...
       CODE_SIGN_STYLE: Automatic
       DEVELOPMENT_TEAM: SEU_TEAM_ID_AQUI  # <-- Insira seu Team ID aqui
   ```
7. No terminal, gere novamente o projeto Xcode executando:
   ```bash
   xcodegen generate
   ```

### 3. Rodando no Dispositivo Físico (AÇÃO MINHA)
1. Abra o projeto recém-gerado no Xcode:
   ```bash
   open HermesVoice.xcodeproj
   ```
2. Conecte o seu iPhone físico ao Mac via cabo USB.
3. No iPhone, desbloqueie a tela e toque em **Confiar neste Computador**.
4. No Xcode, selecione o seu iPhone como o destino da execução (na barra superior, clique na seleção de dispositivos e escolha o seu iPhone em vez de um simulador).
5. Clique no botão de **Run** (ícone de Play ou `Cmd + R`).
6. **Importante na primeira execução:** 
   O iOS impedirá a abertura inicial por questões de segurança. No seu iPhone, vá em:
   **Ajustes → Geral → VPN e Gerenciamento de Dispositivos** e toque em **Autorizar / Confiar** no perfil associado ao seu Apple ID.
7. Execute o app novamente pelo Xcode.

---

## 🚗 Testando no CarPlay (Sem Fio ou Com Fio)

1. Entre no veículo e conecte o iPhone ao CarPlay.
2. Com o app **Hermes Voice** aberto ou em segundo plano, inicie a conversa:
   - **Manualmente:** Toque no grande botão verde no app.
   - **Por Voz (Hands-free):** Diga: *"E aí Siri, conversar com o Hermes"* ou *"E aí Siri, falar com o Hermes"*.
3. A interface nativa de chamada do sistema (com o nome "Hermes") aparecerá na tela do CarPlay do seu carro.
4. O áudio do seu microfone será capturado e processado com o Cancelamento de Eco Acústico (AEC) nativo, impedindo que o retorno do som do carro cause eco no Hermes.
5. Use os controles nativos do volante ou da tela do carro para mutar a chamada ou desligar.

---

## 🔌 Integração do WebSocket com o Hermes

A comunicação WebSocket é gerenciada nativamente no arquivo [HermesAgentClient.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/Hermes/HermesAgentClient.swift).

### Configurações na UI:
Abra o app no iPhone e toque no ícone de engrenagem no canto superior direito para acessar a tela de configurações:
- **URL do WebSocket:** Defina o endpoint (ex: `wss://dashboard.egger.app.br/voice`).
- **Usuário e Senha:** Salvados de forma criptografada no Keychain do aparelho.
- **Idioma do STT:** Padrão `pt-BR`.
- **Velocidade de Voz (TTS):** Slider para controle de velocidade de fala do Hermes.

### Customização do JSON (AÇÃO MINHA):
O protocolo padrão implementado assume as seguintes payloads. Se o seu servidor do Hermes usar chaves diferentes, edite as seções correspondentes indicadas por `TODO` em [HermesAgentClient.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/Hermes/HermesAgentClient.swift):

* **Envio de Fala (Usuário):**
  ```json
  {
    "type": "user_message",
    "text": "Texto transcrito aqui"
  }
  ```
* **Recebimento de Resposta (Hermes - Streaming ou Fim de Resposta):**
  ```json
  // Formato estruturado esperado:
  {
    "type": "token",
    "text": "palavra "
  }
  
  // Ou sinalizador de fim de transmissão:
  {
    "type": "done"
  }
  ```
  *Nota: Se o servidor enviar apenas texto puro (raw strings), a classe está programada para aceitar e acumular as strings diretamente.*

---

## 🛠️ Arquitetura do Projeto

O código-fonte está dividido sob o diretório `Sources/`:
- **App/**
  - [HermesVoiceApp.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/App/HermesVoiceApp.swift): Inicialização da UI.
  - [RootView.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/App/RootView.swift): Painel principal de controle da chamada, animações e feedback visual.
- **Call/**
  - [CallManager.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/Call/CallManager.swift): Gerenciamento da ligação virtual usando CallKit (CXProvider). Garante que a ativação da `AVAudioSession` é feita pelo sistema no momento certo.
- **Audio/**
  - [AudioEngineManager.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/Audio/AudioEngineManager.swift): Captura do microfone usando `AVAudioEngine` combinada com AEC (Acoustic Echo Cancellation) via `setVoiceProcessingEnabled(true)`.
- **Speech/**
  - [SpeechRecognizer.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/Speech/SpeechRecognizer.swift): Transcreve fala em texto localmente (STT) e usa temporizador de 1.2 segundos para detectar o final da frase do usuário.
  - [SpeechSynthesizer.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/Speech/SpeechSynthesizer.swift): Fala de retorno pt-BR via `AVSpeechSynthesizer` vinculada à sessão ativa da ligação.
- **Hermes/**
  - [HermesAgentClient.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/Hermes/HermesAgentClient.swift): Cliente de rede WebSocket com Basic Auth.
- **Session/**
  - [VoiceSession.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/Session/VoiceSession.swift): Orquestrador de estados e sincronizador dos módulos.
- **Intents/**
  - [StartHermesCallIntent.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/Intents/StartHermesCallIntent.swift): Atalhos e intents do app para execução viva-voz via Siri.
- **Settings/**
  - [SettingsStore.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/Settings/SettingsStore.swift): Persistência em UserDefaults.
  - [KeychainStore.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/Settings/KeychainStore.swift): Criptografia de senhas no Keychain.
  - [SettingsView.swift](file:///Users/ildemareggerjunior/Projects/Hermes_Voice/Sources/Settings/SettingsView.swift): UI de configurações.
