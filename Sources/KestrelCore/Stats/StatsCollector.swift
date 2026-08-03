import Foundation
import IOKit
import IOKit.ps
#if canImport(CoreWLAN)
import CoreWLAN
#endif

public struct MemoryStats: Sendable, Equatable {
    public let total: Int64
    public let used: Int64
    public let free: Int64
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public init(total: Int64, used: Int64, free: Int64) {
        self.total = total
        self.used = used
        self.free = free
    }
}

public struct CPUStats: Sendable, Equatable {
    public let coreCount: Int
    /// 1, 5 and 15-minute load averages.
    public let loadAverages: [Double]
    /// Load average (1 min) normalised to cores, as a 0…1+ pressure figure.
    public var pressure: Double { coreCount > 0 ? (loadAverages.first ?? 0) / Double(coreCount) : 0 }

    public init(coreCount: Int, loadAverages: [Double]) {
        self.coreCount = coreCount
        self.loadAverages = loadAverages
    }
}

public struct BatteryStats: Sendable, Equatable {
    public let percent: Int
    public let isCharging: Bool
    public let cycleCount: Int?
    public let healthPercent: Int?

    public init(percent: Int, isCharging: Bool, cycleCount: Int?, healthPercent: Int?) {
        self.percent = percent
        self.isCharging = isCharging
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
    }
}

public struct NetworkStats: Sendable, Equatable {
    public let bytesIn: Int64
    public let bytesOut: Int64
    public let ssid: String?

    public init(bytesIn: Int64, bytesOut: Int64, ssid: String?) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.ssid = ssid
    }
}

public struct VolumeInfo: Sendable, Equatable {
    public let name: String
    public let space: DiskSpace

    public init(name: String, space: DiskSpace) {
        self.name = name
        self.space = space
    }
}

/// Reads live system metrics through public macOS APIs only (no private SPI, so the app
/// stays notarizable). Every method is best-effort: if a metric is unavailable it
/// returns a neutral value or `nil` rather than throwing.
public struct StatsCollector {
    private let fm = FileManager.default

    public init() {}

    // MARK: - Disk

    public func disk(at url: URL = URL(fileURLWithPath: NSHomeDirectory())) -> DiskSpace? {
        DiskUsageReader().space(at: url)
    }

    public func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsBrowsableKey]
        guard let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }
        return urls.compactMap { url in
            guard let space = DiskUsageReader().space(at: url) else { return nil }
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? url.lastPathComponent
            return VolumeInfo(name: name, space: space)
        }
    }

    // MARK: - Memory (Mach host_statistics64)

    public func memory() -> MemoryStats {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemoryStats(total: total, used: 0, free: total)
        }
        let page = Int64(vm_kernel_page_size)
        let active = Int64(stats.active_count) * page
        let wired = Int64(stats.wire_count) * page
        let compressed = Int64(stats.compressor_page_count) * page
        let free = Int64(stats.free_count) * page
        // "App memory + wired + compressed" is the figure Activity Monitor calls used.
        let used = active + wired + compressed
        return MemoryStats(total: total, used: used, free: free)
    }

    // MARK: - CPU (load averages)

    public func cpu() -> CPUStats {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        return CPUStats(coreCount: ProcessInfo.processInfo.activeProcessorCount, loadAverages: loads)
    }

    // MARK: - Battery (IOKit power sources + AppleSmartBattery)

    public func battery() -> BatteryStats? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey as String] as? String) == kIOPSInternalBatteryType else { continue }
            let percent = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let charging = (desc[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
            let (cycles, health) = batteryHealth()
            return BatteryStats(percent: percent, isCharging: charging, cycleCount: cycles, healthPercent: health)
        }
        return nil
    }

    private func batteryHealth() -> (cycles: Int?, healthPercent: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        func intProp(_ key: String) -> Int? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
        }
        let cycles = intProp("CycleCount")
        let design = intProp("DesignCapacity")
        let maxCap = intProp("AppleRawMaxCapacity") ?? intProp("MaxCapacity")
        let health = design.flatMap { d in d > 0 ? maxCap.map { Int(Double($0) / Double(d) * 100) } : nil }
        return (cycles, health)
    }

    // MARK: - Network (getifaddrs + CoreWLAN)

    public func network() -> NetworkStats {
        var totalIn: Int64 = 0
        var totalOut: Int64 = 0
        var addrs: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addrs) == 0 {
            var pointer = addrs
            while let entry = pointer {
                if let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                   (Int32(entry.pointee.ifa_flags) & IFF_UP) != 0,
                   let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    totalIn += Int64(data.pointee.ifi_ibytes)
                    totalOut += Int64(data.pointee.ifi_obytes)
                }
                pointer = entry.pointee.ifa_next
            }
            freeifaddrs(addrs)
        }
        return NetworkStats(bytesIn: totalIn, bytesOut: totalOut, ssid: currentSSID())
    }

    private func currentSSID() -> String? {
        #if canImport(CoreWLAN)
        return CWWiFiClient.shared().interface()?.ssid()
        #else
        return nil
        #endif
    }
}
