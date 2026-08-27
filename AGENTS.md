# Hermes_Voice — instruções para agentes

Branch padrão: `main`. Stack principal: Swift/SwiftUI, XcodeGen, Shell e Python.
Este checkout possui commit local pré-existente à frente de `origin/main`; preserve-o.

Não há workflows GitHub Actions atuais. Qualquer build/CI iOS exige macOS/Xcode e
deve seguir `ildemar_ios-native-testflight`; não tente executar Xcode em runner
Linux. Leia `ildemar-github-actions-self-hosted` antes de criar CI. Não faça deploy,
release, bump, push ou alteração de secrets sem solicitação explícita.
