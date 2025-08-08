import Foundation
import AppKit

enum TemplateEngine {
    static func renderTemplates(for descriptor: ProfileDescriptor) {
        let templatesRoot = descriptor.directory.appendingPathComponent("templates/home", isDirectory: true)
        let outputRoot = descriptor.directory.appendingPathComponent("home", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: templatesRoot.path) else { return }
        let variables = computeVariables(for: descriptor)
        // Do not skip hidden files so templates for dotfiles are rendered
        if let enumerator = fm.enumerator(at: templatesRoot, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            for case let tplURL as URL in enumerator {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: tplURL.path, isDirectory: &isDir), isDir.boolValue { continue }
                let rel = tplURL.path.replacingOccurrences(of: templatesRoot.path + "/", with: "")
                let outURL = outputRoot.appendingPathComponent(rel)
                do {
                    try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let content = try String(contentsOf: tplURL, encoding: .utf8)
                    let rendered = render(content: content, with: variables)
                    try rendered.write(to: outURL, atomically: true, encoding: .utf8)
                } catch {
                    print("Template render error for \(tplURL.lastPathComponent): \(error)")
                }
            }
        }
    }

    static func computeVariables(for descriptor: ProfileDescriptor) -> [String: String] {
        var vars: [String: String] = [:]
        // Load variables.json if present
        let varsURL = descriptor.directory.appendingPathComponent("variables.json")
        if let data = try? Data(contentsOf: varsURL), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in obj {
                vars[k] = String(describing: v)
            }
        }
        // If you want dynamic colors from wallpaper in templates, this can be re-enabled
        return vars
    }

    static func render(content: String, with variables: [String: String]) -> String {
        var result = content
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }
}
