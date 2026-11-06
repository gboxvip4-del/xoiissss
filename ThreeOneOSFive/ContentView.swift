import SwiftUI
import UIKit
import Foundation

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    private static let remotePatchCatalogURL = URL(string: "https://gboxiosvip.com.br/api/v1/patches.php")!
    @State private var selectedGame: BYPASS7Game = .normal
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var brandGlow = false
    @State private var showPatchLibrary = false
    @State private var showOnlinePatches = false

    @State private var pendingApply: BYPASS7PatchRequest?
    @State private var pendingRestore: BYPASS7PatchRequest?
    @State private var pendingChangedRestore: BYPASS7PatchRequest?
    @State private var showApplyConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var showChangedRestoreConfirmation = false
    @State private var changedRestorePaths: [String] = []
    @State private var workingPatchID: UUID?
    @State private var workingOperation: BYPASS7PatchOperation?
    @State private var actionAlert: BYPASS7Alert?
    @State private var remoteActivePatchSlugs = Set<String>()
    @State private var hasLoadedRemoteCatalog = false
    @State private var isRefreshingRemoteCatalog = false
    @State private var remoteCatalogError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(AppTheme.accent.opacity(0.08))
                .frame(height: 0.5)

            aimsScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(AppTheme.accent)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showLogs) {
            LogView()
        }
        .sheet(isPresented: $showPatchLibrary) {
            PatchProjectsView(
                onOpenSettings: { showSettings = true },
                onOpenLogs: { showLogs = true }
            )
        }
        .sheet(isPresented: $showOnlinePatches) {
            RepositoryHomeView(
                onOpenSettings: { showSettings = true },
                onOpenLogs: { showLogs = true }
            )
        }
        .confirmationDialog(
            Text("Ativar \(pendingApply?.definition.displayName ?? "patch")?"),
            isPresented: $showApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Ativar") {
                if let pendingApply { apply(pendingApply) }
                pendingApply = nil
            }
            Button("Cancelar", role: .cancel) { pendingApply = nil }
        } message: {
            Text("O app validará o destino e salvará uma cópia dos arquivos originais antes de aplicar o patch no Free Fire Normal.")
        }
        .confirmationDialog(
            Text("Restaurar os arquivos originais?"),
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restaurar", role: .destructive) {
                if let pendingRestore { prepareRestore(pendingRestore) }
                pendingRestore = nil
            }
            Button("Cancelar", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Feche o Free Fire antes. Os arquivos voltarão ao estado salvo antes da aplicação do patch.")
        }
        .confirmationDialog(
            Text("Alguns arquivos foram alterados"),
            isPresented: $showChangedRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restaurar mesmo assim", role: .destructive) {
                if let pendingChangedRestore {
                    restore(pendingChangedRestore, allowChangedTargets: true)
                }
                pendingChangedRestore = nil
            }
            Button("Cancelar", role: .cancel) { pendingChangedRestore = nil }
        } message: {
            Text(changedRestoreMessage)
        }
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil { showPatchLibrary = true }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil { showPatchLibrary = true }
        }
        .onAppear {
            repositoryStore.refreshAllIfNeeded()
        }
        .task {
            await refreshRemotePatchCatalog()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                showSettings = true
            } label: {
                AppLogo(size: 50)
                    .clipShape(Circle())
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                    }
                    .shadow(color: AppTheme.accent.opacity(0.24), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Perfil e configurações")

            VStack(alignment: .leading, spacing: 3) {
                Text("GBOXIOSVIP")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .shadow(color: AppTheme.accent.opacity(brandGlow ? 0.85 : 0.30), radius: brandGlow ? 12 : 4)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: brandGlow
                    )
                    .onAppear {
                        guard !reduceMotion else { return }
                        brandGlow = true
                    }
                    .onChange(of: reduceMotion) { shouldReduceMotion in
                        brandGlow = !shouldReduceMotion
                    }
            }
            Spacer(minLength: 12)
            Button {
                showOnlinePatches = true
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.07))
                        .frame(width: 44, height: 44)
                    Image(systemName: "cloud.arrow.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Patches online")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.consoleBackground.ignoresSafeArea(edges: .top))
    }

    private var aimsScreen: some View {
        ZStack {
            GameScreenBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 23, weight: .black))
                            .foregroundStyle(AppTheme.accent)
                            .shadow(color: AppTheme.accent.opacity(0.85), radius: 10)
                            .accessibilityHidden(true)

                        AnimatedGameTitle()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .padding(.bottom, 18)

                    gameSelector
                    whatsappChannelButton

                    HStack(spacing: 11) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(LinearGradient(colors: [AppTheme.accent.opacity(0.2), Color.cyan.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .frame(width: 38, height: 38)
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(AppTheme.accent.opacity(0.38), lineWidth: 0.8)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("CENTRAL DE ATIVAÇÃO")
                                .font(.system(size: 12, weight: .heavy))
                                .tracking(1.2)
                                .foregroundStyle(.white)
                            Text(remoteCatalogSummary)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.58))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        Spacer(minLength: 0)
                        Button {
                            Task { await refreshRemotePatchCatalog() }
                        } label: {
                            Group {
                                if isRefreshingRemoteCatalog {
                                    ProgressView().tint(Color.cyan)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.cyan.opacity(0.9))
                                }
                            }
                            .frame(width: 32, height: 32)
                            .background(Color.cyan.opacity(0.08), in: Circle())
                            .overlay {
                                Circle().strokeBorder(Color.cyan.opacity(0.24), lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isRefreshingRemoteCatalog)
                        .accessibilityLabel("Atualizar catálogo do servidor")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [AppTheme.accent.opacity(0.35), Color.cyan.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                    patchCard

                    if selectedGame == .max {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(AppTheme.accent)
                            Text("Os patches e o reset de conta convidado são para Free Fire Normal.")
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                        .font(.system(size: 12))
                        .padding(.top, 12)
                    }

                    if hasUnmappedLegacyPatch {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.accent)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Há um patch HS de uma versão anterior ativo.")
                                    .foregroundStyle(.primary)
                                Button("Gerenciar e restaurar") { showPatchLibrary = true }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                        .font(.system(size: 12))
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 22)
            }
        }
    }

    private var gameSelector: some View {
        HStack(spacing: 5) {
            gameButton(.normal)
            gameButton(.max)
        }
        .padding(5)
        .background(
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.075, blue: 0.09), Color(red: 0.025, green: 0.035, blue: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.85), Color.cyan.opacity(0.65), Color.purple.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
        }
        .shadow(color: Color.cyan.opacity(0.13), radius: 14, y: 4)
    }

    private func gameButton(_ game: BYPASS7Game) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedGame = game
            }
        } label: {
            Text(game.title)
                .font(.system(size: 12, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(selectedGame == game ? Color.white : Color(uiColor: .secondaryLabel))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if selectedGame == game {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.accent, Color(red: 0.02, green: 0.55, blue: 0.62)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.cyan.opacity(0.34), radius: 9, y: 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedGame == game ? .isSelected : [])
    }

    private var whatsappChannelButton: some View {
        Link(destination: URL(string: "https://whatsapp.com/channel/0029VbC4Nlc2ER6YstkeMR38")!) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("CANAL DO WHATSAPP")
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(0.55)
                        .foregroundStyle(.white)
                    Text("Acompanhe novidades e avisos")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.76))
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.48, blue: 0.29), Color(red: 0.02, green: 0.32, blue: 0.30), Color(red: 0.025, green: 0.22, blue: 0.31)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(red: 0.31, green: 0.95, blue: 0.55).opacity(0.9), Color.cyan.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color(red: 0.10, green: 0.82, blue: 0.42).opacity(0.18), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir canal do WhatsApp")
        .padding(.top, 14)
    }

    private var patchCard: some View {
        VStack(spacing: 0) {
            if patchStore.isBusy {
                HStack(spacing: 10) {
                    ProgressView().tint(AppTheme.accent)
                    Text("Carregando patches...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                    Spacer()
                }
                .padding(18)
            } else if !hasLoadedRemoteCatalog {
                HStack(spacing: 10) {
                    ProgressView().tint(AppTheme.accent)
                    Text("Consultando o catálogo do servidor...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                    Spacer()
                }
                .padding(18)
            } else if let remoteCatalogError {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Catálogo indisponível", systemImage: "wifi.exclamationmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.orange)
                    Text(remoteCatalogError)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                    Button {
                        Task { await refreshRemotePatchCatalog() }
                    } label: {
                        Label("Tentar novamente", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                }
                .padding(16)
            } else if activeRemotePatchCount == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.cyan.opacity(0.8))
                    Text("Nenhuma função ativa no painel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("As funções desativadas no site ficam ocultas aqui.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            } else {
                remoteManagedPatchRows
            }
        }
        .padding(7)
        .background {
            ZStack(alignment: .trailing) {
                LinearGradient(
                    colors: [Color(red: 0.025, green: 0.06, blue: 0.055), Color(red: 0.035, green: 0.035, blue: 0.075), Color(red: 0.02, green: 0.025, blue: 0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image("ActivationPanelMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .opacity(0.24)
                    .padding(.trailing, 12)
                    .accessibilityHidden(true)
                LinearGradient(
                    colors: [Color.black.opacity(0.04), Color.black.opacity(0.16)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.8), Color.cyan.opacity(0.58), Color.purple.opacity(0.42)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )
        }
        .shadow(color: Color.cyan.opacity(0.12), radius: 16, y: 5)
    }

    private var activeStandardDefinitions: [BYPASS7PatchDefinition] {
        visibleDefinitions(in: BYPASS7PatchCatalog.definitions)
    }

    private var activeTextureDefinitions: [BYPASS7PatchDefinition] {
        visibleDefinitions(in: BYPASS7PatchCatalog.textureDefinitions)
    }

    private var activeGuestResetDefinitions: [BYPASS7PatchDefinition] {
        visibleDefinitions(in: BYPASS7PatchCatalog.guestResetDefinitions)
    }

    private var activeRemotePatchCount: Int {
        visibleDefinitions(in: BYPASS7PatchCatalog.allDefinitions).count
    }

    private var remoteCatalogSummary: String {
        if isRefreshingRemoteCatalog { return "Sincronizando catálogo do servidor..." }
        if remoteCatalogError != nil { return "Catálogo indisponível · funções ocultas" }
        guard hasLoadedRemoteCatalog else { return "Consultando catálogo do servidor..." }
        let count = activeRemotePatchCount
        return count == 1 ? "1 função habilitada no servidor" : "\(count) funções habilitadas no servidor"
    }

    private func visibleDefinitions(in definitions: [BYPASS7PatchDefinition]) -> [BYPASS7PatchDefinition] {
        definitions.filter { remoteActivePatchSlugs.contains($0.id) }
    }

    @ViewBuilder
    private var remoteManagedPatchRows: some View {
        if !activeStandardDefinitions.isEmpty {
            patchRows(for: activeStandardDefinitions)
        }

        if !activeStandardDefinitions.isEmpty
            && (!activeTextureDefinitions.isEmpty || !activeGuestResetDefinitions.isEmpty) {
            Rectangle()
                .fill(AppTheme.accent.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 12)
        }

        if !activeTextureDefinitions.isEmpty {
            Text("TEXTURAS")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 5)
            patchRows(for: activeTextureDefinitions)
        }

        if !activeTextureDefinitions.isEmpty && !activeGuestResetDefinitions.isEmpty {
            Rectangle()
                .fill(AppTheme.accent.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 12)
        }

        if !activeGuestResetDefinitions.isEmpty {
            Text("RESETAR CONTA CONVIDADO")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 5)
            patchRows(for: activeGuestResetDefinitions)
        }
    }

    @MainActor
    private func refreshRemotePatchCatalog() async {
        guard !isRefreshingRemoteCatalog else { return }
        isRefreshingRemoteCatalog = true
        defer { isRefreshingRemoteCatalog = false }

        var request = URLRequest(url: Self.remotePatchCatalogURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  data.count <= 512_000 else {
                throw URLError(.badServerResponse)
            }

            let catalog = try JSONDecoder().decode(RemotePatchCatalogResponse.self, from: data)
            guard catalog.status == "success",
                  catalog.domain.caseInsensitiveCompare("gboxiosvip.com.br") == .orderedSame else {
                throw URLError(.cannotParseResponse)
            }

            remoteActivePatchSlugs = Set(catalog.data.compactMap { normalizedRemoteSlug($0.slug) })
            remoteCatalogError = nil
            hasLoadedRemoteCatalog = true
        } catch {
            remoteActivePatchSlugs = []
            remoteCatalogError = "Não foi possível consultar o servidor. Tente novamente; as funções ficam ocultas enquanto não houver confirmação da API."
            hasLoadedRemoteCatalog = true
        }
    }

    private func normalizedRemoteSlug(_ value: String) -> String? {
        let slug = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isValid = slug.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
        return isValid ? slug : nil
    }

    @ViewBuilder
    private func patchRows(for definitions: [BYPASS7PatchDefinition]) -> some View {
        ForEach(definitions) { definition in
            let item = patchItem(for: definition)
            let active = item.map(isPatchActive) ?? false
            let isPendingActivation = item.map { pendingApply?.item.id == $0.id } ?? false
            let blockedByHS = isBlockedByAnotherHighSensitivity(definition, active: active)
            let rowStatus = isPendingActivation
                ? (text: "Confirme para ativar", icon: "checkmark.circle")
                : (blockedByHS
                    ? (text: "Outro HS está ativo", icon: "lock.fill")
                    : status(for: definition, item: item, active: active))
            PatchActivationRow(
                definition: definition,
                isOn: active || isPendingActivation,
                status: rowStatus.text,
                statusIcon: rowStatus.icon,
                isActive: active,
                isWorking: item.map { workingPatchID == $0.id } ?? false,
                isEnabled: item?.project != nil
                    && workingPatchID == nil
                    && pendingApply == nil
                    && !blockedByHS
                    && (isCompatibleWithSelectedGame(definition) || active),
                onToggle: { enabled in requestPatchChange(enabled, definition: definition) }
            )
            if definition.id != definitions.last?.id {
                Rectangle()
                    .fill(AppTheme.accent.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.leading, 12)
            }
        }
    }

    private var homeScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Text("GBOXIOSVIP")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.top, 34)

                Text("Sua central de patches")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))

                HStack(spacing: 12) {
                    homeInfoCard(value: "\(BYPASS7PatchCatalog.allDefinitions.count)", title: "PATCHES", icon: "scope")
                    homeInfoCard(value: "NORMAL", title: "FREE FIRE", icon: "gamecontroller.fill")
                }
                .padding(.top, 4)

            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
    }

    private func homeInfoCard(value: String, title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.patchCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.cardOutline, lineWidth: 1)
        }
    }

    private func patchItem(for definition: BYPASS7PatchDefinition) -> PatchLibraryItem? {
        let expectedNames = Set(definition.matchNames.map(normalizedName))
        if let packageID = definition.packageID,
           let exactMatch = patchStore.items.first(where: { $0.id == packageID }) {
            return exactMatch
        }
        let matches = patchStore.items.filter { item in
            let projectName = item.project?.name
            let fileName = item.packageURL.deletingPathExtension().lastPathComponent
            return [projectName, Optional(fileName)]
                .compactMap { $0 }
                .map(normalizedName)
                .contains(where: expectedNames.contains)
        }

        if let active = matches.first(where: isPatchActive) { return active }
        if definition.isHighSensitivity,
           let legacyActive = matches.first(where: {
               $0.id == BYPASS7PatchCatalog.legacySharedHighSensitivityID
                   && isPatchActive($0)
           }) {
            return legacyActive
        }
        return matches.first(where: { $0.id != BYPASS7PatchCatalog.legacySharedHighSensitivityID })
            ?? matches.first
    }

    private func normalizedName(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func isPatchActive(_ item: PatchLibraryItem) -> Bool {
        DevicePatchService.latestReceipt(projectID: item.id) != nil
    }

    private var activeHighSensitivityPatchID: UUID? {
        BYPASS7PatchCatalog.allDefinitions
            .filter(\.isHighSensitivity)
            .compactMap { patchItem(for: $0) }
            .first(where: isPatchActive)?.id
    }

    private func isBlockedByAnotherHighSensitivity(
        _ definition: BYPASS7PatchDefinition,
        active: Bool
    ) -> Bool {
        guard definition.isHighSensitivity, !active else { return false }
        return activeHighSensitivityPatchID != nil || hasUnmappedLegacyPatch
    }

    private func status(
        for definition: BYPASS7PatchDefinition,
        item: PatchLibraryItem?,
        active: Bool
    ) -> (text: String, icon: String) {
        if item.map({ workingPatchID == $0.id }) == true {
            return workingOperation == .restoring
                ? ("Restaurando...", "arrow.uturn.backward.circle")
                : ("Ativando...", "arrow.triangle.2.circlepath")
        }
        if active { return ("Ativado", "checkmark.circle.fill") }
        if let item, item.project == nil { return ("Pacote bloqueado", "lock.fill") }
        if !isCompatibleWithSelectedGame(definition) {
            return (
                "Somente Free Fire Normal",
                "info.circle"
            )
        }
        if item == nil {
            return (patchStore.isBusy ? "Carregando..." : "Pacote indisponível", "exclamationmark.circle")
        }
        return (definition.offStatus, definition.offStatusIcon)
    }

    private func requestPatchChange(_ shouldActivate: Bool, definition: BYPASS7PatchDefinition) {
        guard let item = patchItem(for: definition) else {
            actionAlert = BYPASS7Alert(
                title: "Patch indisponível",
                message: "Não encontrei o pacote \(definition.displayName) nesta build. Abra a biblioteca e atualize os patches."
            )
            return
        }
        let request = BYPASS7PatchRequest(item: item, definition: definition)
        if shouldActivate {
            guard isCompatibleWithSelectedGame(definition) else { return }
            pendingApply = request
            showApplyConfirmation = true
        } else {
            pendingRestore = request
            showRestoreConfirmation = true
        }
    }

    private func isCompatibleWithSelectedGame(_ definition: BYPASS7PatchDefinition) -> Bool {
        selectedGame == .normal
    }

    private func apply(_ request: BYPASS7PatchRequest) {
        guard let baseProject = request.item.project else {
            actionAlert = BYPASS7Alert(title: "Patch indisponível", message: "Este pacote precisa ser desbloqueado antes de ser ativado.")
            return
        }
        workingPatchID = request.item.id
        workingOperation = .applying
        let item = request.item
        let store = patchStore

        Task.detached(priority: .userInitiated) {
            do {
                let shouldSynchronizeWorkspace = request.definition.synchronizesWorkspaceBeforeApply
                    && item.summary.schemaVersion >= 2
                    && item.canInspectContents
                let project = shouldSynchronizeWorkspace
                    ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
                    : baseProject
                _ = try DevicePatchService.apply(project: project)
                await MainActor.run {
                    store.reload()
                    workingPatchID = nil
                    workingOperation = nil
                    actionAlert = BYPASS7Alert(title: "Patch ativado", message: "\(request.definition.displayName) foi aplicado. O switch ficará ativo enquanto este patch estiver instalado.")
                }
            } catch let error as PatchPackageError {
                log("patch: activation failed for \(request.definition.displayName) [\(request.item.id.uuidString)]: \(error.errorDescription ?? String(describing: error))")
                await MainActor.run {
                    workingPatchID = nil
                    workingOperation = nil
                    actionAlert = alert(for: error, restoring: false)
                }
            } catch {
                log("patch: unexpected activation failure for \(request.definition.displayName) [\(request.item.id.uuidString)]: \(error.localizedDescription)")
                await MainActor.run {
                    workingPatchID = nil
                    workingOperation = nil
                    let details = error.localizedDescription
                    actionAlert = BYPASS7Alert(
                        title: "Falha ao ativar",
                        message: details.isEmpty
                            ? "Não foi possível aplicar o patch. Feche o Free Fire e tente novamente."
                            : "Não foi possível aplicar o patch. \(details)"
                    )
                }
            }
        }
    }

    private func prepareRestore(_ request: BYPASS7PatchRequest) {
        guard let receipt = DevicePatchService.latestReceipt(projectID: request.item.id) else {
            patchStore.reload()
            actionAlert = BYPASS7Alert(title: "Patch já desativado", message: "Não há uma aplicação ativa deste patch para restaurar.")
            return
        }
        workingPatchID = request.item.id
        workingOperation = .restoring

        Task.detached(priority: .userInitiated) {
            do {
                let inspection = try DevicePatchService.inspectRestore(receipt: receipt)
                if inspection.changedTargets.isEmpty {
                    try DevicePatchService.restore(receipt: receipt)
                    await MainActor.run {
                        patchStore.reload()
                        workingPatchID = nil
                        workingOperation = nil
                        actionAlert = BYPASS7Alert(title: "Patch desativado", message: "Os arquivos originais foram restaurados.")
                    }
                } else {
                    await MainActor.run {
                        workingPatchID = nil
                        workingOperation = nil
                        changedRestorePaths = inspection.changedTargets.map(\.displayPath)
                        pendingChangedRestore = request
                        showChangedRestoreConfirmation = true
                    }
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    workingPatchID = nil
                    workingOperation = nil
                    actionAlert = alert(for: error, restoring: true)
                }
            } catch {
                await MainActor.run {
                    workingPatchID = nil
                    workingOperation = nil
                    actionAlert = BYPASS7Alert(title: "Falha ao verificar restauração", message: "Não foi possível verificar os arquivos do patch.")
                }
            }
        }
    }

    private func restore(_ request: BYPASS7PatchRequest, allowChangedTargets: Bool) {
        guard let receipt = DevicePatchService.latestReceipt(projectID: request.item.id) else {
            patchStore.reload()
            return
        }
        workingPatchID = request.item.id
        workingOperation = .restoring

        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.restore(
                    receipt: receipt,
                    allowChangedTargets: allowChangedTargets
                )
                await MainActor.run {
                    patchStore.reload()
                    workingPatchID = nil
                    workingOperation = nil
                    actionAlert = BYPASS7Alert(title: "Patch desativado", message: "Os arquivos originais foram restaurados.")
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    workingPatchID = nil
                    workingOperation = nil
                    actionAlert = alert(for: error, restoring: true)
                }
            } catch {
                await MainActor.run {
                    workingPatchID = nil
                    workingOperation = nil
                    actionAlert = BYPASS7Alert(title: "Falha ao restaurar", message: "Não foi possível restaurar os arquivos originais.")
                }
            }
        }
    }

    private func alert(for error: PatchPackageError, restoring: Bool) -> BYPASS7Alert {
        if case let .targetOccupied(path) = error {
            return BYPASS7Alert(
                title: "Outro patch está ativo",
                message: "Esse destino já está sendo usado por outro patch. Desative o patch atual antes de ativar outro.\n\n\(path)"
            )
        }
        if case let .targetAppUnavailable(bundleID) = error {
            let target = bundleID == "com.dts.freefireth" ? "Free Fire Normal" : bundleID
            return BYPASS7Alert(
                title: "Jogo não encontrado",
                message: "Não foi possível localizar o app \(target) no dispositivo."
            )
        }
        let fallback = restoring
            ? "Não foi possível restaurar os arquivos originais."
            : "Não foi possível aplicar o patch."
        return BYPASS7Alert(
            title: restoring ? "Falha ao restaurar" : "Falha ao ativar",
            message: error.errorDescription ?? fallback
        )
    }

    private var changedRestoreMessage: String {
        var visiblePaths = changedRestorePaths.prefix(5).joined(separator: "\n")
        if changedRestorePaths.count > 5 { visiblePaths += "\n…" }
        return "Alguns arquivos mudaram depois da aplicação:\n\(visiblePaths)\n\nO app fará um backup do estado atual antes de restaurar."
    }

    private var hasUnmappedLegacyPatch: Bool {
        guard DevicePatchService.latestReceipt(
            projectID: BYPASS7PatchCatalog.legacySharedHighSensitivityID
        ) != nil else { return false }
        return !BYPASS7PatchCatalog.definitions
            .filter(\.isHighSensitivity)
            .contains { patchItem(for: $0)?.id == BYPASS7PatchCatalog.legacySharedHighSensitivityID }
    }
}

private struct GameScreenBackdrop: View {
    var body: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.09, blue: 0.075), Color.black, Color(red: 0.025, green: 0.035, blue: 0.085)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(AppTheme.accent.opacity(0.075))
                .frame(width: 320, height: 320)
                .offset(x: -150, y: -280)
            Circle()
                .fill(Color.cyan.opacity(0.06))
                .frame(width: 300, height: 300)
                .offset(x: 170, y: 80)
        }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
private struct AnimatedGameTitle: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gradientOffset: CGFloat = -1.0

    private var titleGradient: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [
                Color(red: 0.00, green: 0.66, blue: 0.22),
                Color(red: 0.00, green: 0.88, blue: 0.31),
                Color(red: 0.42, green: 1.00, blue: 0.55),
                Color(red: 0.04, green: 0.96, blue: 0.36),
                Color(red: 0.00, green: 0.58, blue: 0.19),
                Color(red: 0.12, green: 1.00, blue: 0.40),
                Color(red: 0.00, green: 0.66, blue: 0.22)
            ]
            : [
                Color(red: 0.00, green: 0.43, blue: 0.15),
                Color(red: 0.00, green: 0.67, blue: 0.23),
                Color(red: 0.03, green: 0.84, blue: 0.31),
                Color(red: 0.00, green: 0.55, blue: 0.19),
                Color(red: 0.00, green: 0.73, blue: 0.25),
                Color(red: 0.03, green: 0.84, blue: 0.31),
                Color(red: 0.00, green: 0.43, blue: 0.15)
            ]

        let visibleOffset: CGFloat = reduceMotion ? 0.0 : gradientOffset
        return LinearGradient(
            colors: colors,
            startPoint: UnitPoint(x: visibleOffset, y: 0.5),
            endPoint: UnitPoint(x: visibleOffset + 1.0, y: 0.5)
        )
    }

    var body: some View {
        Text("FREE FIRE")
            .font(.system(size: 25, weight: .black, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(titleGradient)
            .shadow(color: AppTheme.accent.opacity(0.28), radius: 8)
            .animation(
                reduceMotion ? nil : .linear(duration: 2.4).repeatForever(autoreverses: false),
                value: gradientOffset
            )
            .onAppear {
                guard !reduceMotion else { return }
                gradientOffset = 1.0
            }
            .onChange(of: reduceMotion) { shouldReduceMotion in
                gradientOffset = shouldReduceMotion ? -1.0 : 1.0
            }
    }
}

private struct PatchActivationRow: View {
    let definition: BYPASS7PatchDefinition
    let isOn: Bool
    let status: String
    let statusIcon: String
    let isActive: Bool
    let isWorking: Bool
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gradientOffset: CGFloat = -1.0

    private var titleGradient: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [
                Color(red: 0.00, green: 0.66, blue: 0.22),
                Color(red: 0.00, green: 0.88, blue: 0.31),
                Color(red: 0.42, green: 1.00, blue: 0.55),
                Color(red: 0.04, green: 0.96, blue: 0.36),
                Color(red: 0.00, green: 0.58, blue: 0.19),
                Color(red: 0.12, green: 1.00, blue: 0.40),
                Color(red: 0.00, green: 0.66, blue: 0.22)
            ]
            : [
                Color(red: 0.00, green: 0.43, blue: 0.15),
                Color(red: 0.00, green: 0.67, blue: 0.23),
                Color(red: 0.03, green: 0.84, blue: 0.31),
                Color(red: 0.00, green: 0.55, blue: 0.19),
                Color(red: 0.00, green: 0.73, blue: 0.25),
                Color(red: 0.03, green: 0.84, blue: 0.31),
                Color(red: 0.00, green: 0.43, blue: 0.15)
            ]

        let visibleOffset: CGFloat = reduceMotion ? 0.0 : gradientOffset
        return LinearGradient(
            colors: colors,
            startPoint: UnitPoint(x: visibleOffset, y: 0.5),
            endPoint: UnitPoint(x: visibleOffset + 1.0, y: 0.5)
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(definition.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(titleGradient)
                        .animation(
                            reduceMotion ? nil : .linear(duration: 2.4).repeatForever(autoreverses: false),
                            value: gradientOffset
                        )
                        .onAppear {
                            guard !reduceMotion else { return }
                            gradientOffset = 1.0
                        }
                        .onChange(of: reduceMotion) { shouldReduceMotion in
                            gradientOffset = shouldReduceMotion ? -1.0 : 1.0
                        }
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Text("NORMAL")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(Color.cyan.opacity(0.9))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.09), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.cyan.opacity(0.3), lineWidth: 0.7)
                    }
                }
                Text(status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? AppTheme.accent : (isEnabled ? Color.cyan.opacity(0.82) : Color(uiColor: .secondaryLabel)))
                    .lineLimit(2)
            }

            Spacer(minLength: 3)

            if isWorking {
                ProgressView()
                    .tint(AppTheme.accent)
                    .frame(width: 48)
            } else {
                Button {
                    onToggle(!isOn)
                } label: {
                    ZStack(alignment: isOn ? .trailing : .leading) {
                        Capsule(style: .continuous)
                            .fill(
                                isOn
                                    ? LinearGradient(colors: [AppTheme.accent, Color.cyan], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.09)], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: 46, height: 28)
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [AppTheme.accent.opacity(isOn ? 0.95 : 0.35), Color.cyan.opacity(isOn ? 0.8 : 0.25)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            }
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .shadow(color: .black.opacity(0.20), radius: 2, y: 1)
                            .padding(3)
                    }
                    .frame(width: 48, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel(definition.displayName)
                .accessibilityValue(status)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isActive
                            ? [AppTheme.accent.opacity(0.12), Color.cyan.opacity(0.045)]
                            : [Color.white.opacity(0.045), Color.white.opacity(0.018)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: isActive
                            ? [AppTheme.accent.opacity(0.78), Color.cyan.opacity(0.65)]
                            : [Color.cyan.opacity(0.25), AppTheme.accent.opacity(0.17)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isActive ? 1.15 : 0.7
                )
        }
        .shadow(color: isActive ? AppTheme.accent.opacity(0.12) : .clear, radius: 8, y: 2)
    }
}

private enum BYPASS7Game: Int {
    case normal
    case max

    var title: String {
        self == .normal ? "FREE FIRE NORMAL" : "FREE FIRE MAX"
    }
}

private enum BYPASS7PatchOperation: Equatable {
    case applying
    case restoring
}

private struct BYPASS7PatchDefinition: Identifiable {
    let id: String
    let displayName: String
    let matchNames: [String]
    let offStatus: String
    let offStatusIcon: String
    let isHighSensitivity: Bool
    let synchronizesWorkspaceBeforeApply: Bool
    let packageID: UUID?

    init(
        id: String,
        displayName: String,
        matchNames: [String],
        offStatus: String,
        offStatusIcon: String,
        isHighSensitivity: Bool,
        synchronizesWorkspaceBeforeApply: Bool = true,
        packageID: UUID? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.matchNames = matchNames
        self.offStatus = offStatus
        self.offStatusIcon = offStatusIcon
        self.isHighSensitivity = isHighSensitivity
        self.synchronizesWorkspaceBeforeApply = synchronizesWorkspaceBeforeApply
        self.packageID = packageID
    }
}

private enum BYPASS7PatchCatalog {
    static let legacySharedHighSensitivityID = UUID(
        uuidString: "C11E1C4D-CAC4-4FC7-ACF2-4E6BECA09CEB"
    )!

    static let definitions: [BYPASS7PatchDefinition] = [
        BYPASS7PatchDefinition(
            id: "hs-pescoco",
            displayName: "HS PESCOÇO - ALTO COM ANTENA",
            matchNames: [
                "HS PESCOÇO - ALTO COM ANTENA",
                "HS PESCOÇO + ALTO COM ANTENA"
            ],
            offStatus: "Estado não verificado",
            offStatusIcon: "questionmark.circle",
            isHighSensitivity: true
        ),
        BYPASS7PatchDefinition(
            id: "hs-peito",
            displayName: "HS PEITO COM ANTENA",
            matchNames: ["HS PEITO COM ANTENA"],
            offStatus: "Estado não verificado",
            offStatusIcon: "questionmark.circle",
            isHighSensitivity: true
        ),
        BYPASS7PatchDefinition(
            id: "hs-barriga-com-antena",
            displayName: "HS BARRIGA COM ANTENA",
            matchNames: ["HS BARRIGA COM ANTENA"],
            offStatus: "Estado não verificado",
            offStatusIcon: "questionmark.circle",
            isHighSensitivity: true
        ),
        BYPASS7PatchDefinition(
            id: "bala-magica-com-antena",
            displayName: "BALA MÁGICA COM ANTENA",
            matchNames: ["BALA MÁGICA COM ANTENA"],
            offStatus: "Estado não verificado",
            offStatusIcon: "questionmark.circle",
            isHighSensitivity: true
        )
    ]

    static let textureDefinitions: [BYPASS7PatchDefinition] = [
        BYPASS7PatchDefinition(
            id: "textura-pantera",
            displayName: "TEXTURA PANTERA",
            matchNames: ["💕 TEXTURA PANTERA", "TEXTURA PANTERA"],
            offStatus: "Desativado",
            offStatusIcon: "xmark.circle",
            isHighSensitivity: false,
            synchronizesWorkspaceBeforeApply: false,
            packageID: UUID(uuidString: "EA96471F-42F2-48F0-800E-E23A55A85B7D")
        )
    ]

    static let guestResetDefinitions: [BYPASS7PatchDefinition] = [
        BYPASS7PatchDefinition(
            id: "guest-reset",
            displayName: "RESET GUEST",
            matchNames: [
                "RESET GUEST",
                "RESET ACC WMCRYVIETNAM",
                "[FFT] RESET ACC WMCRYVIETNAM",
                "[FFM] RESET ACC WMCRYVIETNAM",
                "[FFT] XOA ACC KHACH (@WMCRYVIETNAM)",
                "[FFT] XÓA ACC KHÁCH (@WMCRYVIETNAM)",
                "[FFM] XOA ACC KHACH (@WMCRYVIETNAM)",
                "[FFM] XÓA ACC KHÁCH (@WMCRYVIETNAM)"
            ],
            offStatus: "Desativado",
            offStatusIcon: "xmark.circle",
            isHighSensitivity: false,
            synchronizesWorkspaceBeforeApply: false
        )
    ]

    static var allDefinitions: [BYPASS7PatchDefinition] {
        definitions + textureDefinitions + guestResetDefinitions
    }
}

private struct BYPASS7PatchRequest {
    let item: PatchLibraryItem
    let definition: BYPASS7PatchDefinition
}

private struct BYPASS7Alert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct RemotePatchCatalogResponse: Decodable {
    let status: String
    let domain: String
    let data: [RemotePatchCatalogItem]
}

private struct RemotePatchCatalogItem: Decodable {
    let slug: String
}
