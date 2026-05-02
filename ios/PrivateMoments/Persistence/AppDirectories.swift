import Foundation

enum AppDirectories {
    static func applicationSupportDirectory() throws -> URL {
        let url = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "PrivateMoments", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func databaseURL() throws -> URL {
        try applicationSupportDirectory().appending(path: "private-moments.sqlite")
    }

    static func mediaDirectory() throws -> URL {
        let url = try applicationSupportDirectory()
            .appending(path: "media", directoryHint: .isDirectory)
            .appending(path: "compressed", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func draftMediaDirectory() throws -> URL {
        let url = try applicationSupportDirectory()
            .appending(path: "draft-media", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func localFilePath(fromStoredPath storedPath: String) throws -> String {
        guard !storedPath.isEmpty else {
            return ""
        }

        if !storedPath.hasPrefix("/") {
            return try appending(relativePath: storedPath, to: applicationSupportDirectory()).path
        }

        if FileManager.default.fileExists(atPath: storedPath) {
            return storedPath
        }

        if let relativePath = try relativePath(fromLocalPath: storedPath) {
            return try appending(relativePath: relativePath, to: applicationSupportDirectory()).path
        }

        let fileName = URL(fileURLWithPath: storedPath).lastPathComponent
        return try mediaDirectory().appending(path: fileName).path
    }

    static func storedPath(forLocalPath localPath: String) throws -> String {
        guard !localPath.isEmpty else {
            return ""
        }

        if !localPath.hasPrefix("/") {
            return localPath
        }

        if let relativePath = try relativePath(fromLocalPath: localPath) {
            return relativePath
        }

        let fileName = URL(fileURLWithPath: localPath).lastPathComponent
        return "media/compressed/\(fileName)"
    }

    private static func relativePath(fromLocalPath localPath: String) throws -> String? {
        let normalizedPath = URL(fileURLWithPath: localPath).standardizedFileURL.path
        let supportPath = try applicationSupportDirectory().standardizedFileURL.path

        if normalizedPath == supportPath {
            return ""
        }

        let supportPrefix = "\(supportPath)/"
        if normalizedPath.hasPrefix(supportPrefix) {
            return String(normalizedPath.dropFirst(supportPrefix.count))
        }

        if let range = normalizedPath.range(of: "/PrivateMoments/") {
            return String(normalizedPath[range.upperBound...])
        }

        return nil
    }

    private static func appending(relativePath: String, to baseURL: URL) -> URL {
        relativePath
            .split(separator: "/")
            .reduce(baseURL) { url, component in
                url.appending(path: String(component))
            }
    }
}
