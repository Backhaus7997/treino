//
//  ContentView.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F1.
//

import SwiftUI

/// Pantalla de estado del emparejamiento.
///
/// Deliberadamente austera: F1 solo entrega credencial. La pantalla del
/// entreno llega en F2, cuando el reloj pueda leer la rutina.
struct ContentView: View {
    @EnvironmentObject private var coordinator: CredentialCoordinator

    var body: some View {
        VStack(spacing: 8) {
            switch coordinator.state {
            case .waitingForPairing:
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .imageScale(.large)
                Text("Abrí TREINO en el teléfono para vincular el reloj")
                    .font(.footnote)
                    .multilineTextAlignment(.center)

            case .exchanging:
                ProgressView()
                Text("Vinculando…")
                    .font(.footnote)

            case .ready:
                Image(systemName: "checkmark.circle")
                    .imageScale(.large)
                    .foregroundStyle(.green)
                Text("Listo para entrenar")
                    .font(.footnote)

            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .imageScale(.large)
                    .foregroundStyle(.orange)
                Text("No se pudo vincular. Abrí TREINO en el teléfono.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(CredentialCoordinator())
}
