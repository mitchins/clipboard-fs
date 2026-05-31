import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    typealias FetchLatestRelease = @Sendable () async throws -> (tagName: String, htmlURL: URL)

    @Published var state: State = .idle

    enum State {
        case idle
        case checking
        case upToDate(version: String)
        case available(current: String, latest: String, url: URL)
        case failed(String)
    }

    private let apiURL = URL(string: "https://api.github.com/repos/mitchins/clipdisk/releases/latest")!
    private let fetchLatestRelease: FetchLatestRelease

    init(fetchLatestRelease: FetchLatestRelease? = nil) {
        if let fetchLatestRelease {
            self.fetchLatestRelease = fetchLatestRelease
        } else {
            let apiURL = self.apiURL
            self.fetchLatestRelease = {
                var request = URLRequest(url: apiURL)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, _) = try await URLSession.shared.data(for: request)
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                return (tagName: release.tagName, htmlURL: release.htmlURL)
            }
        }
    }

    func check(current: String) {
        if case .checking = state { return }
        state = .checking

        Task {
            do {
                let release = try await fetchLatestRelease()
                let latest = release.tagName.trimmingCharacters(in: .init(charactersIn: "v"))
                let clean = current.trimmingCharacters(in: .init(charactersIn: "v"))
                if latest == clean {
                    state = .upToDate(version: current)
                } else {
                    state = .available(current: current, latest: release.tagName, url: release.htmlURL)
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
