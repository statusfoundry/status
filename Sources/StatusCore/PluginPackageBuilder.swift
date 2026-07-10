import Foundation

public enum PluginPackageBuilderError: Error, Equatable, LocalizedError, Sendable {
    case noJSONFiles(String)
    case invalidFileName(String)
    case fileTooLarge(String)

    public var errorDescription: String? {
        switch self {
        case .noJSONFiles(let path):
            "Plugin folder contains no supported package files: \(path)"
        case .invalidFileName(let name):
            "Plugin package file name is invalid: \(name)"
        case .fileTooLarge(let name):
            "Plugin package file is too large for the v1 stored ZIP builder: \(name)"
        }
    }
}

public enum PluginPackageBuilder {
    public static func packageData(fromDirectory directory: URL, fileManager: FileManager = .default) throws -> Data {
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
            .filter { url in
                url.pathExtension == "json" || url.lastPathComponent == "icon.svg" || url.lastPathComponent == "README.md"
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard fileURLs.isEmpty == false else {
            throw PluginPackageBuilderError.noJSONFiles(directory.path)
        }

        let files = try fileURLs.map { url in
            try PluginPackageFile(name: url.lastPathComponent, data: Data(contentsOf: url))
        }
        return try packageData(files: files)
    }

    public static func packageData(files: [PluginPackageFile]) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for file in files.sorted(by: { $0.name < $1.name }) {
            guard file.name.range(of: #"^[A-Za-z0-9._-]+\.json$"#, options: .regularExpression) != nil || file.name == "icon.svg" || file.name == "README.md" else {
                throw PluginPackageBuilderError.invalidFileName(file.name)
            }
            guard file.data.count <= Int(UInt32.max) else {
                throw PluginPackageBuilderError.fileTooLarge(file.name)
            }

            let nameData = Data(file.name.utf8)
            var localHeader = Data()
            localHeader.appendUInt32LE(0x0403_4b50)
            localHeader.appendUInt16LE(20)
            localHeader.appendUInt16LE(0)
            localHeader.appendUInt16LE(0)
            localHeader.appendUInt16LE(0)
            localHeader.appendUInt16LE(0)
            localHeader.appendUInt32LE(0)
            localHeader.appendUInt32LE(UInt32(file.data.count))
            localHeader.appendUInt32LE(UInt32(file.data.count))
            localHeader.appendUInt16LE(UInt16(nameData.count))
            localHeader.appendUInt16LE(0)
            localHeader.append(nameData)

            var centralHeader = Data()
            centralHeader.appendUInt32LE(0x0201_4b50)
            centralHeader.appendUInt16LE(20)
            centralHeader.appendUInt16LE(20)
            centralHeader.appendUInt16LE(0)
            centralHeader.appendUInt16LE(0)
            centralHeader.appendUInt16LE(0)
            centralHeader.appendUInt16LE(0)
            centralHeader.appendUInt32LE(0)
            centralHeader.appendUInt32LE(UInt32(file.data.count))
            centralHeader.appendUInt32LE(UInt32(file.data.count))
            centralHeader.appendUInt16LE(UInt16(nameData.count))
            centralHeader.appendUInt16LE(0)
            centralHeader.appendUInt16LE(0)
            centralHeader.appendUInt16LE(0)
            centralHeader.appendUInt16LE(0)
            centralHeader.appendUInt32LE(0)
            centralHeader.appendUInt32LE(offset)
            centralHeader.append(nameData)

            archive.append(localHeader)
            archive.append(file.data)
            centralDirectory.append(centralHeader)
            offset += UInt32(localHeader.count + file.data.count)
        }

        archive.append(centralDirectory)
        archive.appendUInt32LE(0x0605_4b50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(UInt16(files.count))
        archive.appendUInt16LE(UInt16(files.count))
        archive.appendUInt32LE(UInt32(centralDirectory.count))
        archive.appendUInt32LE(offset)
        archive.appendUInt16LE(0)
        return archive
    }
}

public struct PluginPackageFile: Equatable, Sendable {
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }
}
