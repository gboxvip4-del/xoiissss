import SwiftUI
import UIKit

/// Bloqueio de acesso baseado exclusivamente no IP público liberado pela API.
/// Não possui login, campo de chave ou botão de ativação.
struct AccessGateView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    @State private var contentVisible = false

    var body: some View {
        ZStack {
            LoginBackdrop(accent: AppTheme.accent)

            VStack(spacing: 18) {
                AppLogo(size: 76)

                Text("GBOXIOSVIP")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                if viewModel.isLoading {
                    ProgressView()
                        .tint(AppTheme.accent)
                    Text("Verificando IP...")
                        .foregroundStyle(Color.white.opacity(0.76))
                } else if viewModel.showError {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.40))

                    Text("IP NÃO LIBERADO")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.40, blue: 0.40))

                    Text("Libere este IP no site proxy e volte ao aplicativo.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.76))

                    Text("O acesso permanece bloqueado até a API confirmar a liberação.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.50))
                } else {
                    Text("Verificando acesso por IP...")
                        .foregroundStyle(Color.white.opacity(0.76))
                }
            }
            .padding(30)
            .frame(maxWidth: 380)
            .background(
                Color(red: 0.012, green: 0.030, blue: 0.018),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppTheme.accent.opacity(0.42), lineWidth: 1)
            }
            .opacity(contentVisible ? 1 : 0)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.24)) {
                contentVisible = true
            }
        }
        .onChange(of: viewModel.activationURL) { newURL in
            guard let newURL else { return }
            UIApplication.shared.open(newURL)
            viewModel.activationURL = nil
        }
    }
}

// Mantido apenas para os componentes visuais existentes do projeto.
private struct LoginBackdrop: View {
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color.black, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [accent.opacity(0.30), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 380
                )

                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    path.move(to: CGPoint(x: 0, y: height * 0.18))
                    path.addLine(to: CGPoint(x: width * 0.27, y: height * 0.10))
                    path.addLine(to: CGPoint(x: width * 0.42, y: height * 0.21))
                    path.move(to: CGPoint(x: width, y: height * 0.72))
                    path.addLine(to: CGPoint(x: width * 0.76, y: height * 0.80))
                    path.addLine(to: CGPoint(x: width * 0.92, y: height * 0.92))
                }
                .stroke(accent.opacity(0.18), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct AuthenticatedRootView: View {
    var body: some View {
        ContentView()
    }
}
