import Foundation
import IOKit
import IOKit.hid
import IOKit.ps

// MARK: - System Statistics Models
struct SystemStats {
    let cpuUsage: Double
    let memoryUsage: MemoryUsage
    let diskUsage: DiskUsage
    let temperature: TemperatureReading?
}

struct MemoryUsage {
    let used: UInt64
    let total: UInt64
    let percentage: Double
}

struct DiskUsage {
    let used: UInt64
    let total: UInt64
    let percentage: Double
}

struct TemperatureReading {
    let celsius: Double
    let sensorName: String
}

// MARK: - System Monitor Class
class SystemMonitor: ObservableObject {
    @Published var currentStats = SystemStats(
        cpuUsage: 0.0,
        memoryUsage: MemoryUsage(used: 0, total: 0, percentage: 0.0),
        diskUsage: DiskUsage(used: 0, total: 0, percentage: 0.0),
        temperature: nil
    )
    
    private var timer: Timer?
    private var refreshInterval: TimeInterval = 2.0
    
    // For CPU calculation
    private var previousCPUInfo: [natural_t]?
    private let temperatureReader = TemperatureReader()
    
    init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            self.updateStats()
        }
        updateStats() // Initial update
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func updateRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        stopMonitoring()
        startMonitoring()
    }
    
    private func updateStats() {
        DispatchQueue.global(qos: .background).async {
            let cpuUsage = self.getCPUUsage()
            let memoryUsage = self.getMemoryUsage()
            let diskUsage = self.getDiskUsage()
            let temperature = self.temperatureReader.cpuTemperature()
            
            DispatchQueue.main.async {
                self.currentStats = SystemStats(
                    cpuUsage: cpuUsage,
                    memoryUsage: memoryUsage,
                    diskUsage: diskUsage,
                    temperature: temperature
                )
            }
        }
    }
    
    // MARK: - CPU Usage Calculation
    private func getCPUUsage() -> Double {
        return getSystemWideCPUUsage()
    }
    
    private func getSystemWideCPUUsage() -> Double {
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0
        
        let result = host_processor_info(mach_host_self(),
                                       PROCESSOR_CPU_LOAD_INFO,
                                       &numCpus,
                                       &cpuInfo,
                                       &numCpuInfo)
        
        guard result == KERN_SUCCESS else {
            return 0.0
        }
        
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(numCpuInfo))
        }
        
        var totalUsage: Double = 0.0
        let cpuStateMax = Int(CPU_STATE_MAX)
        
        // Calculate current total ticks for all CPUs
        var currentTotalTicks: [natural_t] = Array(repeating: 0, count: cpuStateMax)
        
        for i in 0..<Int(numCpus) {
            let cpuLoadInfo = cpuInfo.advanced(by: i * cpuStateMax)
            for j in 0..<cpuStateMax {
                currentTotalTicks[j] += natural_t(cpuLoadInfo[j])
            }
        }
        
        if let previousTicks = previousCPUInfo {
            // Calculate differences since last measurement
            let userDiff = currentTotalTicks[Int(CPU_STATE_USER)] - previousTicks[Int(CPU_STATE_USER)]
            let systemDiff = currentTotalTicks[Int(CPU_STATE_SYSTEM)] - previousTicks[Int(CPU_STATE_SYSTEM)]
            let niceDiff = currentTotalTicks[Int(CPU_STATE_NICE)] - previousTicks[Int(CPU_STATE_NICE)]
            let idleDiff = currentTotalTicks[Int(CPU_STATE_IDLE)] - previousTicks[Int(CPU_STATE_IDLE)]
            
            let totalDiff = userDiff + systemDiff + niceDiff + idleDiff
            
            if totalDiff > 0 {
                let usedDiff = userDiff + systemDiff + niceDiff
                totalUsage = (Double(usedDiff) / Double(totalDiff)) * 100.0
            }
        }
        
        // Store current values for next calculation
        previousCPUInfo = currentTotalTicks
        
        return max(0.0, min(100.0, totalUsage))
    }
    
    // MARK: - Memory Usage Calculation
    private func getMemoryUsage() -> MemoryUsage {
        return getSystemWideMemoryUsage()
    }
    
    private func getSystemWideMemoryUsage() -> MemoryUsage {
        var vmStats = vm_statistics64()
        var infoCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &infoCount)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return MemoryUsage(used: 0, total: 0, percentage: 0.0)
        }
        
        let pageSize = UInt64(vm_kernel_page_size)
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        
        // Calculate memory usage to match Activity Monitor's "App Memory"
    _ = UInt64(vmStats.free_count) // free pages not needed for Activity Monitor style metric
    let activePages = UInt64(vmStats.active_count)
    _ = UInt64(vmStats.inactive_count) // inactive not part of App Memory calculation
    let wiredPages = UInt64(vmStats.wire_count)
    let compressedPages = UInt64(vmStats.compressor_page_count)
    _ = UInt64(vmStats.speculative_count) // speculative not used
        
        // App Memory = Active + Wired + Compressed (matches Activity Monitor's "App Memory")
        // This excludes inactive, free, and speculative memory which are not actively used by apps
        let appMemory = (activePages + wiredPages + compressedPages) * pageSize
        
        let percentage = Double(appMemory) / Double(totalMemory) * 100.0
        
        return MemoryUsage(
            used: appMemory,
            total: totalMemory,
            percentage: max(0.0, min(100.0, percentage))
        )
    }

    // MARK: - Disk Usage
    private func getDiskUsage() -> DiskUsage {
        let path = "/" // main volume
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            if let totalSpace = attrs[.systemSize] as? NSNumber,
               let freeSpace = attrs[.systemFreeSize] as? NSNumber {
                let total = totalSpace.uint64Value
                let free = freeSpace.uint64Value
                let used = total > free ? (total - free) : 0
                let percentage = total > 0 ? (Double(used) / Double(total)) * 100.0 : 0.0
                return DiskUsage(
                    used: used,
                    total: total,
                    percentage: max(0.0, min(100.0, percentage))
                )
            }
        } catch {
            // ignore, fall through
        }
        return DiskUsage(used: 0, total: 0, percentage: 0.0)
    }
}

// MARK: - Utility Extensions
extension MemoryUsage {
    var usedGB: Double {
        return Double(used) / (1024 * 1024 * 1024)
    }
    
    var totalGB: Double {
        return Double(total) / (1024 * 1024 * 1024)
    }
    
    var formattedUsed: String {
        if used < 1024 * 1024 * 1024 {
            return String(format: "%.1fMB", Double(used) / (1024 * 1024))
        } else {
            return String(format: "%.1fGB", usedGB)
        }
    }
    
    var formattedTotal: String {
        return String(format: "%.1fGB", totalGB)
    }
}

extension DiskUsage {
    var usedGB: Double { Double(used) / (1024 * 1024 * 1024) }
    var totalGB: Double { Double(total) / (1024 * 1024 * 1024) }
    var formattedUsed: String {
        if used < 1024 * 1024 * 1024 {
            return String(format: "%.1fMB", Double(used) / (1024 * 1024))
        } else {
            return String(format: "%.1fGB", usedGB)
        }
    }
    var formattedTotal: String { String(format: "%.1fGB", totalGB) }
}

extension TemperatureReading {
    func value(in unit: TemperatureUnit) -> Double {
        switch unit {
        case .celsius:
            return celsius
        case .fahrenheit:
            return (celsius * 9.0 / 5.0) + 32.0
        }
    }

    func formatted(unit: TemperatureUnit) -> String {
        String(format: "%.1f %@", value(in: unit), unit.symbol)
    }
}

// MARK: - Temperature Readers
private final class TemperatureReader {
    private let appleSiliconReader = AppleSiliconTemperatureReader()
    private let smcReader = SMCTemperatureReader()

    func cpuTemperature() -> TemperatureReading? {
        appleSiliconReader.cpuTemperature() ?? smcReader.cpuTemperature()
    }
}

private typealias IOHIDEventRef = CFTypeRef
private typealias IOHIDEventSystemClientRef = CFTypeRef

@_silgen_name("IOHIDEventSystemClientCreate")
private func HIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClientRef

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func HIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClientRef, _ matching: CFDictionary)

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func HIDEventSystemClientCopyServices(_ client: IOHIDEventSystemClientRef) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func HIDServiceClientCopyEvent(_ service: IOHIDServiceClient, _ type: Int64, _ options: Int32, _ timestamp: UInt64) -> IOHIDEventRef?

@_silgen_name("IOHIDEventGetFloatValue")
private func HIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: Int32) -> Double

private final class AppleSiliconTemperatureReader {
    private let temperatureEventType: Int64 = 15
    private let temperatureUsagePage = 0xff00
    private let temperatureUsage = 5
    private lazy var eventSystemClient: IOHIDEventSystemClientRef = HIDEventSystemClientCreate(kCFAllocatorDefault)
    private var services: [IOHIDServiceClient]?

    func cpuTemperature() -> TemperatureReading? {
        let dieReadings = temperatureServices().compactMap { service -> Double? in
            guard let product = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String,
                  product.hasPrefix("PMU tdie"),
                  let event = HIDServiceClientCopyEvent(service, temperatureEventType, 0, 0) else {
                return nil
            }

            let celsius = HIDEventGetFloatValue(event, Int32(temperatureEventType << 16))
            guard celsius > 0, celsius < 130 else { return nil }
            return celsius
        }

        guard let hottestDie = dieReadings.max() else { return nil }
        return TemperatureReading(celsius: hottestDie, sensorName: "CPU Die")
    }

    private func temperatureServices() -> [IOHIDServiceClient] {
        if let services { return services }

        let matching: [String: Any] = [
            kIOHIDPrimaryUsagePageKey: temperatureUsagePage,
            kIOHIDPrimaryUsageKey: temperatureUsage
        ]
        HIDEventSystemClientSetMatching(eventSystemClient, matching as CFDictionary)

        let matchedServices = (HIDEventSystemClientCopyServices(eventSystemClient) as? [IOHIDServiceClient]) ?? []
        services = matchedServices
        return matchedServices
    }
}

// MARK: - SMC Temperature Reader
private final class SMCTemperatureReader {
    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPowerLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCBytes {
        var byte0: UInt8 = 0
        var byte1: UInt8 = 0
        var byte2: UInt8 = 0
        var byte3: UInt8 = 0
        var byte4: UInt8 = 0
        var byte5: UInt8 = 0
        var byte6: UInt8 = 0
        var byte7: UInt8 = 0
        var byte8: UInt8 = 0
        var byte9: UInt8 = 0
        var byte10: UInt8 = 0
        var byte11: UInt8 = 0
        var byte12: UInt8 = 0
        var byte13: UInt8 = 0
        var byte14: UInt8 = 0
        var byte15: UInt8 = 0
        var byte16: UInt8 = 0
        var byte17: UInt8 = 0
        var byte18: UInt8 = 0
        var byte19: UInt8 = 0
        var byte20: UInt8 = 0
        var byte21: UInt8 = 0
        var byte22: UInt8 = 0
        var byte23: UInt8 = 0
        var byte24: UInt8 = 0
        var byte25: UInt8 = 0
        var byte26: UInt8 = 0
        var byte27: UInt8 = 0
        var byte28: UInt8 = 0
        var byte29: UInt8 = 0
        var byte30: UInt8 = 0
        var byte31: UInt8 = 0
    }

    private struct SMCKeyData {
        var key: UInt32 = 0
        var version = SMCVersion()
        var powerLimitData = SMCPowerLimitData()
        var keyInfo = SMCKeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes = SMCBytes()
    }

    private struct SMCValue {
        let dataType: String
        let bytes: [UInt8]
    }

    private let kernelIndex: UInt32 = 2
    private let readBytesCommand: UInt8 = 5
    private let readKeyInfoCommand: UInt8 = 9
    private let temperatureSensors: [(key: String, name: String)] = [
        ("TC0P", "CPU Proximity"),
        ("TC0E", "CPU Core"),
        ("TC0D", "CPU Diode"),
        ("TCXC", "CPU PECI")
    ]

    private var connection: io_connect_t = 0

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func cpuTemperature() -> TemperatureReading? {
        guard openConnection() else { return nil }

        for sensor in temperatureSensors {
            guard let value = readValue(forKey: sensor.key),
                  let celsius = decodeTemperature(value),
                  celsius > 0,
                  celsius < 130 else {
                continue
            }

            return TemperatureReading(celsius: celsius, sensorName: sensor.name)
        }

        return nil
    }

    private func openConnection() -> Bool {
        if connection != 0 { return true }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        return IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS
    }

    private func readValue(forKey key: String) -> SMCValue? {
        guard let keyInfo = readKeyInfo(forKey: key), keyInfo.dataSize <= 32 else { return nil }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCharCode(key)
        input.keyInfo = keyInfo
        input.data8 = readBytesCommand

        guard callSMC(input: &input, output: &output) == KERN_SUCCESS,
              output.result == 0 else {
            return nil
        }

        let dataSize = Int(keyInfo.dataSize)
        let data = withUnsafeBytes(of: output.bytes) { rawBuffer in
            Array(rawBuffer.prefix(dataSize))
        }

        return SMCValue(dataType: fourCharString(keyInfo.dataType), bytes: data)
    }

    private func readKeyInfo(forKey key: String) -> SMCKeyInfo? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCharCode(key)
        input.data8 = readKeyInfoCommand

        guard callSMC(input: &input, output: &output) == KERN_SUCCESS,
              output.result == 0 else {
            return nil
        }

        return output.keyInfo
    }

    private func callSMC(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride

        return withUnsafePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    kernelIndex,
                    UnsafeRawPointer(inputPointer),
                    inputSize,
                    UnsafeMutableRawPointer(outputPointer),
                    &outputSize
                )
            }
        }
    }

    private func decodeTemperature(_ value: SMCValue) -> Double? {
        switch value.dataType {
        case "sp78":
            guard value.bytes.count >= 2 else { return nil }
            let rawValue = UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])
            return Double(Int16(bitPattern: rawValue)) / 256.0
        case "flt ":
            guard value.bytes.count >= 4 else { return nil }
            let rawValue = UInt32(value.bytes[0]) << 24 |
                UInt32(value.bytes[1]) << 16 |
                UInt32(value.bytes[2]) << 8 |
                UInt32(value.bytes[3])
            return Double(Float(bitPattern: rawValue))
        default:
            return nil
        }
    }

    private func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    private func fourCharString(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}