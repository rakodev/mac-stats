import Foundation
import IOKit.ps

// MARK: - System Statistics Models
struct SystemStats {
    let cpuUsage: Double
    let memoryUsage: MemoryUsage
}

struct MemoryUsage {
    let used: UInt64
    let total: UInt64
    let percentage: Double
}

// MARK: - System Monitor Class
class SystemMonitor: ObservableObject {
    @Published var currentStats = SystemStats(
        cpuUsage: 0.0,
        memoryUsage: MemoryUsage(used: 0, total: 0, percentage: 0.0)
    )
    
    private var timer: Timer?
    private var refreshInterval: TimeInterval = 2.0
    
    // For CPU calculation
    private var previousCPUInfo: [natural_t]?
    
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
            
            DispatchQueue.main.async {
                self.currentStats = SystemStats(
                    cpuUsage: cpuUsage,
                    memoryUsage: memoryUsage
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
        let freePages = UInt64(vmStats.free_count)
        let activePages = UInt64(vmStats.active_count)
        let inactivePages = UInt64(vmStats.inactive_count)
        let wiredPages = UInt64(vmStats.wire_count)
        let compressedPages = UInt64(vmStats.compressor_page_count)
        let speculativePages = UInt64(vmStats.speculative_count)
        
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