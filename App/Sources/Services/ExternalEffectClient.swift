import Foundation
import AppKit

enum ExternalEffectError: LocalizedError {
    case missingPath(ProfileExternalEffect.Kind)
    case executableNotFound(String)
    case processFailed(String, Int32, String)
    case wallpaperFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPath(let kind):
            return "The \(kind.rawValue) effect has no source path."
        case .executableNotFound(let name):
            return "Could not find the \(name) command-line tool."
        case .processFailed(let command, let status, let output):
            return "\(command) exited with status \(status)\(output.isEmpty ? "" : ": \(output)")"
        case .wallpaperFailed(let message):
            return "Could not set the wallpaper: \(message)"
        }
    }
}

protocol ExternalEffectClient: Sendable {
    func perform(_ effect: ProfileExternalEffect) async throws
}

struct NoOpExternalEffectClient: ExternalEffectClient {
    func perform(_ effect: ProfileExternalEffect) async throws {
        guard let value = ProcessInfo.processInfo.environment["RICEBARMAC_TEST_EFFECT_DELAY_MS"],
              let milliseconds = UInt64(value),
              milliseconds > 0 else { return }
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
}

final class LiveExternalEffectClient: ExternalEffectClient, @unchecked Sendable {
    func perform(_ effect: ProfileExternalEffect) async throws {
        switch effect.kind {
        case .wallpaper:
            guard let path = effect.path else { throw ExternalEffectError.missingPath(effect.kind) }
            let url = URL(fileURLWithPath: path)
            try await MainActor.run {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ExternalEffectError.wallpaperFailed("The image no longer exists at \(url.path).")
                }
                for screen in NSScreen.screens {
                    do {
                        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                    } catch {
                        throw ExternalEffectError.wallpaperFailed(error.localizedDescription)
                    }
                }
            }
        case .reloadAlacritty:
            if let executable = firstExecutable([
                "/opt/homebrew/bin/alacritty",
                "/usr/local/bin/alacritty",
                "/Applications/Alacritty.app/Contents/MacOS/alacritty"
            ]) {
                try await run(executable, arguments: ["msg", "config", "reload"])
            } else {
                try await run("/usr/bin/killall", arguments: ["-USR1", "Alacritty"])
            }
        case .installVSCodeExtensions:
            guard let executable = firstExecutable([
                "/opt/homebrew/bin/code",
                "/usr/local/bin/code",
                "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
            ]) else {
                throw ExternalEffectError.executableNotFound("VS Code")
            }
            for identifier in effect.arguments {
                try Task.checkCancellation()
                try await run(executable, arguments: ["--install-extension", identifier, "--force"])
            }
        case .installCursorExtensions:
            guard let executable = firstExecutable([
                "/opt/homebrew/bin/cursor",
                "/usr/local/bin/cursor",
                "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
            ]) else {
                throw ExternalEffectError.executableNotFound("Cursor")
            }
            for identifier in effect.arguments {
                try Task.checkCancellation()
                try await run(executable, arguments: ["--install-extension", identifier, "--force"])
            }
        case .startupScript:
            guard let path = effect.path else { throw ExternalEffectError.missingPath(effect.kind) }
            try await run("/bin/zsh", arguments: [path])
        }
    }

    private func firstExecutable(_ candidates: [String]) -> String? {
        candidates.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    private func run(_ executable: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = errorPipe
            process.terminationHandler = { process in
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: ExternalEffectError.processFailed(executable, process.terminationStatus, output))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
