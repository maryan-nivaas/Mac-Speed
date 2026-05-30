import Foundation

// On-demand bandwidth test (like fast.com). UNLIKE the passive monitor, this
// DOES open its own network connections — but only while a test is running,
// and only when the user explicitly starts one from the menu. It transfers
// throwaway bytes to/from Cloudflare's public speed-test endpoints
// (speed.cloudflare.com) and sends no personal data. Results are reported in
// megabits per second (Mbps), the unit fast.com / ISPs use.
//
// Each phase runs for a fixed time window. To keep the connection saturated
// for the whole window (and to stay within Cloudflare's per-request size
// limits), finished streams are immediately replaced with new ones.
final class SpeedTest: NSObject {

    enum Phase { case download, upload, done }

    var onProgress: ((Phase, Double) -> Void)?
    var onFinished: ((Double, Double) -> Void)?

    private var session: URLSession!
    private let lock = NSLock()
    private var byteCount = 0
    private var tasks: [URLSessionTask] = []
    private var sampleTimer: Timer?
    private var cancelled = false
    private var phaseActive = false

    private var phase: Phase = .download
    private var windowStart: Date?
    private var windowStartBytes = 0
    private var lastSampleTime: Date?
    private var lastSampleBytes = 0
    private var finalDown = 0.0
    private var finalUp = 0.0

    private let parallel = 4
    private let measureSeconds = 6.0
    private let rampSeconds = 1.5
    private let downloadChunkBytes = 25_000_000
    private lazy var uploadBody = Data(count: 25 * 1024 * 1024)

    override init() {
        super.init()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.httpMaximumConnectionsPerHost = 8
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    func start() { startDownload() }

    func abort() {
        cancelled = true
        phaseActive = false
        sampleTimer?.invalidate()
        cancelTasks()
        session.invalidateAndCancel()
    }

    // MARK: - thread-safe state
    private func addBytes(_ n: Int) { lock.lock(); byteCount += n; lock.unlock() }
    private func currentBytes() -> Int { lock.lock(); let b = byteCount; lock.unlock(); return b }
    private func trackTask(_ t: URLSessionTask) { lock.lock(); tasks.append(t); lock.unlock() }
    private func cancelTasks() {
        lock.lock(); let copy = tasks; tasks.removeAll(); lock.unlock()
        copy.forEach { $0.cancel() }
    }

    // MARK: - download phase
    private func startDownload() {
        phase = .download
        phaseActive = true
        beginPhase()
        for _ in 0..<parallel { startDownloadStream() }
        DispatchQueue.main.asyncAfter(deadline: .now() + measureSeconds) { [weak self] in
            self?.finishDownload()
        }
    }

    private func startDownloadStream() {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(downloadChunkBytes)")!
        let task = session.dataTask(with: url)
        trackTask(task)
        task.resume()
    }

    private func finishDownload() {
        guard !cancelled else { return }
        phaseActive = false
        sampleTimer?.invalidate()
        finalDown = windowAverageMbps()
        cancelTasks()
        onProgress?(.download, finalDown)
        startUpload()
    }

    // MARK: - upload phase
    private func startUpload() {
        guard !cancelled else { return }
        phase = .upload
        phaseActive = true
        beginPhase()
        for _ in 0..<parallel { startUploadStream() }
        DispatchQueue.main.asyncAfter(deadline: .now() + measureSeconds) { [weak self] in
            self?.finishUpload()
        }
    }

    private func startUploadStream() {
        var req = URLRequest(url: URL(string: "https://speed.cloudflare.com/__up")!)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let task = session.uploadTask(with: req, from: uploadBody)
        trackTask(task)
        task.resume()
    }

    private func finishUpload() {
        guard !cancelled else { return }
        phaseActive = false
        sampleTimer?.invalidate()
        finalUp = windowAverageMbps()
        cancelTasks()
        phase = .done
        onProgress?(.upload, finalUp)
        onFinished?(finalDown, finalUp)
    }

    // MARK: - sampling
    private func beginPhase() {
        lock.lock(); byteCount = 0; lock.unlock()
        windowStart = nil
        windowStartBytes = 0
        lastSampleTime = Date()
        lastSampleBytes = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + rampSeconds) { [weak self] in
            guard let self, !self.cancelled else { return }
            self.windowStartBytes = self.currentBytes()
            self.windowStart = Date()
        }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        sampleTimer = t
    }

    private func sample() {
        guard !cancelled else { return }
        let now = Date()
        let b = currentBytes()
        if let lt = lastSampleTime {
            let dt = now.timeIntervalSince(lt)
            if dt > 0 {
                let instMbps = max(Double(b - lastSampleBytes) * 8 / dt / 1_000_000, 0)
                onProgress?(phase, instMbps)
            }
        }
        lastSampleTime = now
        lastSampleBytes = b
    }

    private func windowAverageMbps() -> Double {
        guard let ws = windowStart else { return 0 }
        let dt = Date().timeIntervalSince(ws)
        guard dt > 0 else { return 0 }
        return Double(currentBytes() - windowStartBytes) * 8 / dt / 1_000_000
    }
}

extension SpeedTest: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if phase == .download { addBytes(data.count) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        if phase == .upload { addBytes(Int(bytesSent)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !cancelled, phaseActive else { return }
        switch phase {
        case .download: startDownloadStream()
        case .upload: startUploadStream()
        case .done: break
        }
    }
}
