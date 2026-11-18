import Foundation

struct QEMUBootConfiguration {
    let machine: String
    let arguments: [String]
    let overlayDirectory: URL
}

enum PreparedFirmwareBundleError: LocalizedError {
    case inaccessibleFolder
    case missingKBoot
    case missingNAND
    case missingBootROM
    case missingIBoot
    case missingNOR
    case emptyNAND
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .inaccessibleFolder:
            return "The selected folder could not be accessed."
        case .missingKBoot:
            return "kboot.bin was not found at the top level of the selected folder."
        case .missingNAND:
            return "The nand folder was not found beside the boot files."
        case .missingBootROM:
            return "bootrom_s5l8900 was not found in the prepared iPhone 2G folder."
        case .missingIBoot:
            return "iBoot.bin was not found in the prepared iPhone 2G folder."
        case .missingNOR:
            return "nor.bin was not found in the prepared iPhone 2G folder."
        case .emptyNAND:
            return "The nand folder contains no files."
        case .copyFailed(let message):
            return message
        }
    }
}

enum PreparedFirmwareBundleStore {
    static func importBundle(from source: URL, device: String = "n90ap") throws -> URL {
        let didStart = source.startAccessingSecurityScopedResource()
        defer {
            if didStart { source.stopAccessingSecurityScopedResource() }
        }

        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PreparedFirmwareBundleError.inaccessibleFolder
        }
        try validate(source, device: device)

        let support = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let parent = support.appendingPathComponent("PreparedFirmware", isDirectory: true)
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)

        let destination = parent.appendingPathComponent("\(device)-device", isDirectory: true)
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        do {
            try manager.copyItem(at: source, to: destination)
            try validate(destination, device: device)
            return destination
        } catch {
            if manager.fileExists(atPath: destination.path) {
                try? manager.removeItem(at: destination)
            }
            throw PreparedFirmwareBundleError.copyFailed(error.localizedDescription)
        }
    }

    static func makeBootConfiguration(bundleURL: URL, storageGiB: Int, device: String = "n90ap") throws -> QEMUBootConfiguration {
        try validate(bundleURL, device: device)
        let manager = FileManager.default
        let overlay = bundleURL.appendingPathComponent("qemu-overlay", isDirectory: true)
        try manager.createDirectory(at: overlay, withIntermediateDirectories: true)

        let nand = bundleURL.appendingPathComponent("nand", isDirectory: true).path
        let arguments: [String]
        let machine: String
        if device == "m68ap" {
            let bootrom = bundleURL.appendingPathComponent("bootrom_s5l8900").path
            let iboot = bundleURL.appendingPathComponent("iBoot.bin").path
            let norSource = bundleURL.appendingPathComponent("nor.bin")
            let norWritable = overlay.appendingPathComponent("nor.bin")
            if !manager.fileExists(atPath: norWritable.path) {
                try manager.copyItem(at: norSource, to: norWritable)
            }
            arguments = [
                "-M", "iPhone-2G,bootrom=\(bootrom),iboot=\(iboot),nand=\(nand),nand-overlay=\(overlay.path)",
                "-drive", "if=pflash,format=raw,file=\(norWritable.path)",
                "-display", "none",
                "-serial", "stdio",
                "-audio", "driver=none"
            ]
            machine = "iPhone-2G (m68ap)"
        } else {
            let kboot = bundleURL.appendingPathComponent("kboot.bin").path
            arguments = [
                "-M", "iPhone-4,kboot=\(kboot),nand=\(nand),nand-overlay=\(overlay.path),nor-rw=\(overlay.appendingPathComponent("nor.bin").path)",
                "-display", "none",
                "-serial", "stdio"
            ]
            machine = "iPhone-4 (n90ap)"
        }
        // The NAND geometry in a prepared bundle is authoritative. Resizing it
        // safely requires regenerating the NAND images, not changing a UI value.
        _ = storageGiB
        return QEMUBootConfiguration(machine: machine, arguments: arguments, overlayDirectory: overlay)
    }

    private static func validate(_ folder: URL, device: String) throws {
        let manager = FileManager.default
        if device == "m68ap" {
            guard manager.fileExists(atPath: folder.appendingPathComponent("bootrom_s5l8900").path) else {
                throw PreparedFirmwareBundleError.missingBootROM
            }
            guard manager.fileExists(atPath: folder.appendingPathComponent("iBoot.bin").path) else {
                throw PreparedFirmwareBundleError.missingIBoot
            }
            guard manager.fileExists(atPath: folder.appendingPathComponent("nor.bin").path) else {
                throw PreparedFirmwareBundleError.missingNOR
            }
        } else if !manager.fileExists(atPath: folder.appendingPathComponent("kboot.bin").path) {
            throw PreparedFirmwareBundleError.missingKBoot
        }

        let nand = folder.appendingPathComponent("nand", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: nand.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PreparedFirmwareBundleError.missingNAND
        }

        let enumerator = manager.enumerator(at: nand, includingPropertiesForKeys: [.isRegularFileKey])
        var hasFile = false
        while let item = enumerator?.nextObject() as? URL {
            if (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                hasFile = true
                break
            }
        }
        guard hasFile else { throw PreparedFirmwareBundleError.emptyNAND }
    }
}
