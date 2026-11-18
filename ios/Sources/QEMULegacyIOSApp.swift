import SwiftUI
import UniformTypeIdentifiers

@_silgen_name("qemu_podium_jit_prepare")
private func qemu_podium_jit_prepare() -> Int32

@_silgen_name("qemu_podium_jit_debugger_attached")
private func qemu_podium_jit_debugger_attached() -> Int32

@main
struct QEMULegacyIOSApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var firmwareURL: URL?
    @State private var preparedBundleURL: URL?
    @State private var showingImporter = false
    @State private var showingBundleImporter = false
    @State private var showingFirmwareBrowser = false
    @State private var isStarting = false
    @State private var status = "Ready to configure the guest"
    @State private var showingEngineNotice = false

    @AppStorage("guestStorageGiB") private var storageGiB = 8
    @AppStorage("allowExperimentalBoots") private var allowExperimentalBoots = false
    @AppStorage("allowUnsignedFirmware") private var allowUnsignedFirmware = false
    @AppStorage("guestIOSVersion") private var guestIOSVersion = "7.1.2"
    @AppStorage("guestCPUFamily") private var cpuFamily = "A4"
    @AppStorage("appAppearance") private var appAppearance = "system"
    @AppStorage("liquidGlassEnabled") private var liquidGlassEnabled = false

    private var selectedColorScheme: ColorScheme? {
        switch appAppearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        NavigationStack {
            mainScreen
        }
        .preferredColorScheme(selectedColorScheme)
        .onAppear {
            migrateLegacyAppearanceSetting()
        }
    }

    @ViewBuilder
    private func cardBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if liquidGlassEnabled {
            if #available(iOS 26.0, *) {
                shape.fill(.ultraThinMaterial)
                    .glassEffect(.regular, in: shape)
            } else {
                shape.fill(.thinMaterial)
            }
        } else {
            shape.fill(.thinMaterial)
        }
    }

    private func migrateLegacyAppearanceSetting() {
        guard appAppearance == "liquidGlass" else { return }
        if #available(iOS 26.0, *) {
            liquidGlassEnabled = true
        }
        appAppearance = "system"
    }

    private var mainScreen: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 12)
            deviceIdentity
            deviceInfoStrip
            firmwareCard
            startButton
            statusMessage
            Spacer()
            Text("Experimental front end · Firmware is not included")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .navigationTitle("Project Astra")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    EmulatorSettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Emulator Settings")
            }
        }
        .sheet(isPresented: $showingFirmwareBrowser) {
            IPSWFirmwareBrowserView(
                selectedVersion: guestIOSVersion,
                onDownloaded: { url, version in
                    firmwareURL = url
                    guestIOSVersion = version
                    status = "Downloaded iOS \(version) IPSW. QEMU runtime is not connected yet."
                },
                deviceIdentifier: selectedDeviceIdentifier
            )
        }
        .fileImporter(
            isPresented: $showingBundleImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            importPreparedBundle(result)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "ipsw") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleIPSWImport(result)
        }
        .alert("Emulator engine not connected", isPresented: $showingEngineNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Settings are saved, but this IPA does not yet contain a runnable QEMU engine or A4 boot pipeline. Firmware, storage, jailbreak options will take effect after that runtime is integrated.")
        }
    }

    private var selectedDeviceIdentifier: String {
        switch cpuFamily {
        case "S5L8900-2G": return "iPhone1,1"
        case "ARM11": return "iPhone1,2"
        case "A5": return "iPhone4,1"
        default: return "iPhone3,1"
        }
    }

    private var deviceIdentity: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(deviceTitle)
                .font(.title2.bold())
            Text(deviceSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var deviceTitle: String {
        switch cpuFamily {
        case "S5L8900-2G": return "iPhone 2G · GSM"
        case "ARM11": return "iPhone 3G · GSM"
        case "A5": return "iPhone 4S · GSM"
        default: return "iPhone 4 · GSM"
        }
    }

    private var deviceSubtitle: String {
        switch cpuFamily {
        case "S5L8900-2G": return "S5L8900 · m68ap · iOS \(guestIOSVersion)"
        case "ARM11": return "S5L8900 · N82AP · iOS \(guestIOSVersion)"
        case "A5": return "A5 · n94ap · iOS \(guestIOSVersion)"
        default: return "A4 · n90ap · iOS \(guestIOSVersion)"
        }
    }

    private var deviceInfoStrip: some View {
        HStack(spacing: 18) {
            Label("Wi-Fi", systemImage: "wifi")
            Label("\(storageGiB) GiB NAND", systemImage: "internaldrive")
            Label(cpuFamily == "S5L8900-2G" || cpuFamily == "ARM11" ? "128 MiB RAM" : "512 MiB RAM", systemImage: "memorychip")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(cardBackground(cornerRadius: 12))
    }

    private var firmwareCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Guest firmware", systemImage: "doc.zipper")
                .font(.headline)
            Text(firmwareURL?.lastPathComponent ?? "No IPSW selected")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button {
                showingFirmwareBrowser = true
            } label: {
                Label("Download from IPSW.me", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                showingImporter = true
            } label: {
                Label("Choose IPSW from Files", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Divider()
            Label("Prepared QEMU device", systemImage: "externaldrive.badge.checkmark")
                .font(.headline)
            Text(preparedBundleURL?.lastPathComponent ?? "No FirmwareKit device bundle imported")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button {
                showingBundleImporter = true
            } label: {
                Label("Import prepared device folder", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Text("Select the FirmwareKit output folder containing kboot.bin and the nand folder. The app validates and copies it into its private storage.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(cornerRadius: 16))
    }

    private var startButton: some View {
        Button {
            startEmulator()
        } label: {
            Label(isStarting ? "Starting…" : "Start Emulator", systemImage: "power")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isStarting)
    }

    private var statusMessage: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
            Text(status)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func handleIPSWImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            firmwareURL = urls.first
            status = firmwareURL == nil
                ? "No firmware selected."
                : "IPSW selected. The QEMU engine still needs to be integrated."
        case .failure(let error):
            status = "Could not open firmware: \(error.localizedDescription)"
        }
    }

    private func importPreparedBundle(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let source = urls.first else {
                status = "No device folder selected."
                return
            }
            do {
                let device = cpuFamily == "S5L8900-2G" ? "m68ap" : "n90ap"
                preparedBundleURL = try PreparedFirmwareBundleStore.importBundle(from: source, device: device)
                status = device == "m68ap"
                    ? "Prepared original iPhone firmware validated. SecureROM, iBoot, NOR and NAND are ready for the QEMU launch stage."
                    : "Prepared iPhone 4 firmware validated. KBoot and NAND are ready for the QEMU launch stage."
            } catch {
                preparedBundleURL = nil
                status = "Prepared bundle rejected: \(error.localizedDescription)"
            }
        case .failure(let error):
            status = "Could not import prepared device folder: \(error.localizedDescription)"
        }
    }

    private func startEmulator() {
        if cpuFamily == "ARM11" {
            status = "iPhone 3G (N82AP) is not wired into this app yet. Its separate board and firmware profile cannot use the iPhone 2G bundle."
            showingEngineNotice = true
            return
        }
        guard let bundle = preparedBundleURL else {
            status = "Import a FirmwareKit-prepared device folder first. An IPSW by itself is not bootable."
            showingBundleImporter = true
            return
        }
        if allowUnsignedFirmware && !allowExperimentalBoots {
            status = "Enable Experimental boots before trying unsigned firmware."
            return
        }
        do {
            let device = cpuFamily == "S5L8900-2G" ? "m68ap" : "n90ap"
            let configuration = try PreparedFirmwareBundleStore.makeBootConfiguration(
                bundleURL: bundle,
                storageGiB: storageGiB,
                device: device
            )
            status = "Boot configuration prepared for \(configuration.machine). QEMU's iOS runtime is not linked into this IPA yet."
        } catch {
            status = "Could not prepare QEMU boot configuration: \(error.localizedDescription)"
        }
        showingEngineNotice = true
    }
}

struct EmulatorSettingsView: View {
    @AppStorage("guestStorageGiB") private var storageGiB = 8
    @AppStorage("installCydiaAfterJailbreak") private var installJailbreak = false
    @AppStorage("allowExperimentalBoots") private var allowExperimentalBoots = false
    @AppStorage("allowUnsignedFirmware") private var allowUnsignedFirmware = false
    @AppStorage("guestIOSVersion") private var guestIOSVersion = "7.1.2"
    @AppStorage("preferJIT") private var preferJIT = true
    @State private var jitStatus = "Not checked"
    @State private var showingSHSHImporter = false
    @State private var importedSHSHName = UserDefaults.standard.string(forKey: "importedIOS613SHSHName") ?? ""
    @AppStorage("guestCPUFamily") private var cpuFamily = "A4"
    @AppStorage("enableDRAv6") private var enableDRAv6 = false
    @AppStorage("draBlobMode") private var draBlobMode = "import"
    @AppStorage("prepareIOS613OTA") private var prepareIOS613OTA = false
    @AppStorage("appAppearance") private var appAppearance = "system"
    @AppStorage("liquidGlassEnabled") private var liquidGlassEnabled = false

    private let storageOptions = [1, 2, 4, 8, 16, 32]
    private var firmwareOptions: [String] {
        switch cpuFamily {
        case "S5L8900-2G": return ["3.1.3"]
        case "ARM11": return ["4.2.1"]
        default: return ["4.2.1", "7.1.2", "6.1.3", "5.1.1", "8.4.1", "9.3.6"]
        }
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("App theme", selection: $appAppearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Text("System follows your iPhone's appearance setting. Light and Dark override it for the entire emulator app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if #available(iOS 26.0, *) {
                    Toggle("Liquid Glass design", isOn: $liquidGlassEnabled)
                    Text("Applies the iOS 26 Liquid Glass materials to Project Astra's custom cards. Turn it off to use the standard material styling.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("Liquid Glass design", isOn: .constant(false))
                        .disabled(true)
                    Text("Requires iOS 26 or later. Project Astra's standard interface remains available on iOS 17 and later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Guest device") {
                Picker("CPU / device family", selection: $cpuFamily) {
                    Text("A4 · iPhone 4").tag("A4")
                    Text("A5 · iPhone 4S (experimental)").tag("A5")
                    Text("S5L8900 · iPhone 2G (experimental)").tag("S5L8900-2G")
                    Text("S5L8900 · iPhone 3G (experimental)").tag("ARM11")
                }
                if cpuFamily == "S5L8900-2G" || cpuFamily == "ARM11" {
                    let isOriginalIPhone = cpuFamily == "S5L8900-2G"
                    Label(
                        isOriginalIPhone
                            ? "Original iPhone (m68ap / iPhone1,1): S5L8900 / ARM1176JZF-S, 128 MiB RAM. iOS 3.1.3 is the final firmware profile. It needs its own board setup and S5L8900 boot ROM."
                            : "iPhone 3G (N82AP / iPhone1,2): same S5L8900 / ARM1176JZF-S family, 128 MiB RAM. iOS 4.2.1 (8C148) is the final firmware profile. It needs its own board setup and NAND/NOR preparation.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Text("The CPU family can be shared, but the 2G and 3G are separate device targets. Neither S5L8900 board is connected to the app's QEMU runtime yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if cpuFamily == "A5" {
                    Label("A5 / iPhone 4S is an experimental target. The current QEMU build only has the iPhone 4 A4 machine; selecting A5 does not add A5 emulation.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Picker("NAND storage", selection: $storageGiB) {
                    ForEach(storageOptions, id: \.self) { size in
                        Text("\(size) GiB").tag(size)
                    }
                }
                Text("Changes the requested virtual NAND capacity. Existing guest data may not fit if you reduce the size.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if cpuFamily != "ARM11" && cpuFamily != "S5L8900-2G" {
            Section("iOS 6.1.3 OTA downgrade") {
                if cpuFamily == "A5" {
                    Toggle("Prepare iOS 6.1.3 OTA downgrade", isOn: $prepareIOS613OTA)
                    Text("Supported for the iPhone 4S (A5). This uses the signed iOS 6.1.3 OTA restore path; changing SystemVersion.plist alone is not enough. The actual restore still requires the Legacy iOS Kit host workflow and a compatible physical-device connection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if prepareIOS613OTA {
                        Label("A5 / iPhone 4S is an eligible OTA target. This preference is saved, but restore execution is not integrated into this iOS app.", systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                } else {
                    Label("Not supported: iPhone 4 (A4) is not listed for the iOS 6.1.3 OTA downgrade.", systemImage: "xmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("The iPhone 4 GSM has a separate downgrade route (for example, powdersn0w with the required compatible blobs); it must not use the iPhone 4S OTA procedure.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            }

            if cpuFamily == "A5" {
                Section("DRA v6 · iOS 6 restore") {
                    Toggle("Use DRA v6 workflow", isOn: $enableDRAv6)
                    if enableDRAv6 {
                        Picker("SHSH blob setup", selection: $draBlobMode) {
                            Text("Import iOS 6.1.3 blobs").tag("import")
                            Text("Manual preparation").tag("manual")
                        }
                        if draBlobMode == "import" {
                            Button {
                                showingSHSHImporter = true
                            } label: {
                                Label(importedSHSHName.isEmpty ? "Import iOS 6.1.3 SHSH blobs" : "Replace imported blobs", systemImage: "doc.badge.plus")
                            }
                            if !importedSHSHName.isEmpty {
                                Label(importedSHSHName, systemImage: "checkmark.doc")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Manual preparation can be selected here, but DRA v6 itself runs as a restore exploit on a compatible physical iPhone 4S. It cannot be run inside this emulator. You will still need the device-specific iOS 6.1.3 SHSH data for a restore workflow.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("DRA v6 is a physical-device restore method, not an A5 QEMU boot feature. This setting records your preferred workflow only; DRA v6 restore integration is not implemented.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("DRA v6") {
                    Text("Choose A5 · iPhone 4S above to reveal the DRA v6 options.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Firmware") {
                Picker("iOS version", selection: $guestIOSVersion) {
                    ForEach(firmwareOptions, id: \.self) { version in
                        Text("iOS \(version)").tag(version)
                    }
                }
                Toggle("Experimental boots", isOn: $allowExperimentalBoots)
                Toggle("Allow unsigned firmware", isOn: $allowUnsignedFirmware)
                    .disabled(!allowExperimentalBoots)
                if allowUnsignedFirmware {
                    Label("Unsigned firmware may fail before the guest OS starts. This setting does not bypass Apple signature checks or boot-chain restrictions.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Text(cpuFamily == "S5L8900-2G"
                     ? "For iPhone 2G, the final firmware is iOS 3.1.3. Its S5L8900 board and boot ROM path are not integrated yet."
                     : cpuFamily == "ARM11"
                        ? "For iPhone 3G, the final firmware is iOS 4.2.1 (8C148). Its S5L8900 board and NAND/NOR preparation are not integrated yet."
                        : "Only firmware compatible with the selected iPhone 4 target can boot. Selecting a version does not download firmware.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Performance") {
                Toggle("Use JIT when available", isOn: $preferJIT)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("StikDebug Validator")
                        Text(jitStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check") {
                        let result = qemu_podium_jit_prepare()
                        let debugger = qemu_podium_jit_debugger_attached() == 1
                        if result == 1 {
                            jitStatus = "JIT memory validation passed (RWX). QEMU TCG is not connected yet."
                        } else if result == 2 {
                            jitStatus = "StikDebug dual-map validation passed. QEMU TCG is not connected yet."
                        } else {
                            jitStatus = debugger
                                ? "Debugger attached, but JIT memory validation failed"
                                : "JIT unavailable — start JIT with StikDebug, then check again"
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Text("StikDebug Validator checks whether the app can prepare executable JIT memory, including the StikDebug JIT26 dual-mapping path. A successful check does not mean QEMU is using JIT yet; QEMU TCG still needs to be connected to this memory. On iOS 27, start JIT with a compatible StikDebug setup before checking.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Jailbreak") {
                Toggle("Install Jailbreak", isOn: $installJailbreak)
                Text("This option saves your jailbreak preference. Jailbreak execution is not implemented yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Storage, firmware, unsigned-boot and jailbreak settings are saved preferences. JIT availability is probed on the host, but QEMU is not yet linked and these settings are not yet applied to a running guest.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Development status")
            }
        }
        .onChange(of: cpuFamily) { _, newValue in
            if newValue == "S5L8900-2G" {
                guestIOSVersion = "3.1.3"
            } else if newValue == "ARM11" {
                guestIOSVersion = "4.2.1"
            } else if guestIOSVersion == "3.1.3" {
                guestIOSVersion = "7.1.2"
            }
        }
        .navigationTitle("Emulator Settings")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingSHSHImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let source = urls.first else { return }
                let accessing = source.startAccessingSecurityScopedResource()
                defer { if accessing { source.stopAccessingSecurityScopedResource() } }
                do {
                    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let ext = source.pathExtension.isEmpty ? "shsh" : source.pathExtension
                    let destination = documents.appendingPathComponent("ios-6.1.3-imported-blobs.\(ext)")
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: source, to: destination)
                    importedSHSHName = source.lastPathComponent
                    UserDefaults.standard.set(importedSHSHName, forKey: "importedIOS613SHSHName")
                    UserDefaults.standard.set(destination.path, forKey: "importedIOS613SHSHPath")
                } catch {
                    importedSHSHName = "Import failed: \(error.localizedDescription)"
                }
            case .failure(let error):
                importedSHSHName = "Import failed: \(error.localizedDescription)"
            }
        }
    }
}
