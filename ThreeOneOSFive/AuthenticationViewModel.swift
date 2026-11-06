import Combine
import Darwin
import Foundation

@MainActor
final class AuthenticationViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var isRevalidating = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var activationURL: URL?

    private let publicIPEndpoint = URL(string: "https://api.ipify.org?format=json")!
    private let validationEndpoint = URL(string: "https://proxy.gboxiosvip.com.br/api/check.php")!
    private let activationPage = URL(string: "https://proxy.gboxiosvip.com.br/")!
    private var hasOpenedActivationPage = false

    private enum ValidationResult {
        case allowed
        case denied(String)
        case offline(String)
    }

    init() {}

    /// Validates only the current public IP. The license/key is entered on the proxy site.
    func login() async {
        guard !isLoading, !isRevalidating else { return }
        isLoading = true
        defer { isLoading = false }

        let result: ValidationResult
        do {
            let ipAddress = try await currentPublicIP()
            result = await validateIPAddress(ipAddress)
        } catch {
            result = .offline(offlineMessage(for: error))
        }

        switch result {
        case .allowed:
            markSessionAuthorized()
            hasOpenedActivationPage = false
        case .denied(let message):
            isAuthenticated = false
            showError = true
            errorMessage = message
            redirectToActivationPage()
        case .offline(let message):
            isAuthenticated = false
            showError = true
            errorMessage = message
        }
    }

    /// Obtains the public IP used by the activation page and by the API check.
    private func currentPublicIP() async throws -> String {
        var request = URLRequest(url: publicIPEndpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw PublicIPError.invalidResponse
        }

        let payload = Self.parseJSONObject(data)
        guard let ipAddress = payload["ip"] as? String,
              Self.isValidIPAddress(ipAddress) else {
            throw PublicIPError.invalidAddress
        }
        return ipAddress
    }

    /// Calls the existing IP-only endpoint: /api/check.php?ip=PUBLIC_IP.
    private func validateIPAddress(_ ipAddress: String) async -> ValidationResult {
        guard var components = URLComponents(
            url: validationEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            return .offline("Não foi possível preparar a validação do IP.")
        }
        components.queryItems = [URLQueryItem(name: "ip", value: ipAddress)]
        guard let url = components.url else {
            return .offline("Não foi possível preparar a validação do IP.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        log("[AUTH] GET GBOX IP validation")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log("[AUTH] IP validation network error")
            return .offline(offlineMessage(for: error))
        }

        guard let http = response as? HTTPURLResponse else {
            return .offline("Erro de conexão com o servidor de validação.")
        }

        log("[AUTH] IP validation HTTP status=\(http.statusCode)")
        let payload = Self.parseJSONObject(data)
        let status = Self.stringFromPayload(payload, keys: ["status", "resultado"]).lowercased()

        // This endpoint authorizes only with status == "ativo".
        if (200...299).contains(http.statusCode), status == "ativo" {
            return .allowed
        }

        if http.statusCode == 429 {
            return .offline(Self.messageFromPayload(payload, fallback: "Muitas tentativas. Aguarde e tente novamente."))
        }
        if (500...599).contains(http.statusCode) {
            return .offline(Self.messageFromPayload(
                payload,
                fallback: "A API GBOX está indisponível no momento (HTTP \(http.statusCode))."
            ))
        }

        return .denied(Self.messageFromPayload(payload, fallback: "IP não liberado. Libere o IP pelo site GBOX VIP."))
    }

    private func redirectToActivationPage() {
        guard !hasOpenedActivationPage else { return }
        hasOpenedActivationPage = true
        activationURL = activationPage
    }

    private static func isValidIPAddress(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        var ipv4Address = in_addr()
        if value.withCString({ inet_pton(AF_INET, $0, &ipv4Address) }) == 1 {
            return true
        }
        var ipv6Address = in6_addr()
        return value.withCString { inet_pton(AF_INET6, $0, &ipv6Address) } == 1
    }

    private func markSessionAuthorized() {
        isAuthenticated = true
        showError = false
        errorMessage = ""
        activationURL = nil
    }

    func logout() {
        isAuthenticated = false
        showError = false
        errorMessage = ""
        hasOpenedActivationPage = false
    }

    private static func parseJSONObject(_ data: Data) -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func messageFromPayload(_ payload: [String: Any], fallback: String) -> String {
        let message = stringFromPayload(payload, keys: ["message", "mensagem", "error", "reason"])
        return message.isEmpty ? fallback : message
    }

    private static func stringFromPayload(_ payload: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let string = payload[key] as? String, !string.isEmpty {
                return string
            }
        }
        return ""
    }

    private enum PublicIPError: LocalizedError {
        case invalidResponse
        case invalidAddress

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Não foi possível descobrir o IP público deste iPhone. Verifique a conexão e tente novamente."
            case .invalidAddress:
                return "O serviço de IP retornou um endereço inválido. Tente novamente."
            }
        }
    }

    private func offlineMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Sem conexão com a internet. Verifique sua rede."
            case .timedOut:
                return "Tempo esgotado ao conectar à API GBOX. Tente novamente."
            default:
                return "Não foi possível conectar à API GBOX: \(urlError.localizedDescription)"
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? "Não foi possível conectar à API GBOX."
    }
}
