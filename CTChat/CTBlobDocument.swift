import Foundation

internal struct CTBlobDocument {
    let data: Data
    let fileExtension: String

    init(messageBody: Any, mimeTypes: [String: String]) throws {
        // FileReader передаёт data URL, а не имя файла или произвольный путь.
        guard let message = messageBody as? String, message.hasPrefix("data:"),
              let separator = message.firstIndex(of: ",") else {
            throw Self.invalidMessage()
        }
        let metadata = message[message.index(message.startIndex, offsetBy: 5)..<separator]
            .split(separator: ";", omittingEmptySubsequences: false)
        guard metadata.count >= 2, metadata.last?.lowercased() == "base64",
              let data = Data(base64Encoded: String(message[message.index(after: separator)...])) else {
            throw Self.invalidMessage()
        }
        let mime = String(metadata[0]).lowercased()
        // Неизвестный или отсутствующий MIME сохраняется как бинарный файл.
        let fileExtension = mimeTypes.keys.sorted().first(where: { mimeTypes[$0] == mime }) ?? "bin"
        self.data = data
        self.fileExtension = fileExtension
    }

    func write(in temporaryDirectory: URL = FileManager.default.temporaryDirectory) throws -> CTBlobFile {
        let directory = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("download." + fileExtension)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: nil)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return CTBlobFile(url: url)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw CTChatError(stage: .download, url: nil, error: error)
        }
    }

    private static func invalidMessage() -> CTChatError {
        return CTChatError(stage: .download, host: nil, code: NSURLErrorCannotDecodeContentData,
                           domain: NSURLErrorDomain)
    }
}

internal final class CTBlobFile {
    let url: URL

    fileprivate init(url: URL) {
        self.url = url
    }

    func remove() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    deinit {
        remove()
    }
}
