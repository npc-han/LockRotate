import Foundation

public struct CommandResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunning: Sendable {
    /// A non-zero exit code is a normal result; only timeouts and launch failures throw.
    func run(executable: URL, arguments: [String], stdin: Data?, timeout: TimeInterval) async throws -> CommandResult
}

public struct ProcessRunner: CommandRunning {
    public init() {}

    public func run(
        executable: URL,
        arguments: [String],
        stdin: Data? = nil,
        timeout: TimeInterval = 10
    ) async throws -> CommandResult {
        let job = Job(executable: executable, arguments: arguments, stdin: stdin, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Blocking waits stay off the cooperative thread pool.
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result { try job.execute() })
                }
            }
        } onCancel: {
            job.cancel()
        }
    }
}

private final class Job: @unchecked Sendable {
    private let executable: URL
    private let arguments: [String]
    private let stdin: Data?
    private let timeout: TimeInterval

    private let process = Process()
    private let lock = NSLock()
    private var launched = false
    private var cancelled = false

    init(executable: URL, arguments: [String], stdin: Data?, timeout: TimeInterval) {
        self.executable = executable
        self.arguments = arguments
        self.stdin = stdin
        self.timeout = timeout
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        // terminate() on a process that has not launched raises an Objective-C exception.
        if launched, process.isRunning { process.terminate() }
    }

    func execute() throws -> CommandResult {
        process.executableURL = executable
        process.arguments = arguments
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = stdin == nil ? FileHandle.nullDevice : inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do {
            try process.run()
        } catch {
            lock.unlock()
            throw SystemError.failed(-1, error.localizedDescription)
        }
        launched = true
        lock.unlock()

        // The parent's copies of the child's ends must be closed or the readers never see EOF.
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()
        try? inPipe.fileHandleForReading.close()

        // Read and write concurrently: a child that fills its stdout pipe while we are
        // still writing its stdin would otherwise deadlock both sides.
        let group = DispatchGroup()
        let out = Box<Data>(Data()), err = Box<Data>(Data())
        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.async(group: group) { out.value = outPipe.fileHandleForReading.readDataToEndOfFile() }
        queue.async(group: group) { err.value = errPipe.fileHandleForReading.readDataToEndOfFile() }
        if let stdin {
            let writer = inPipe.fileHandleForWriting
            // Writing to a child that already exited must fail with EPIPE, not kill us with SIGPIPE.
            _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
            queue.async(group: group) {
                try? writer.write(contentsOf: stdin)
                try? writer.close()
            }
        }

        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            // A grandchild may still hold the pipes open; do not wait for it forever.
            _ = group.wait(timeout: .now() + 2)
            throw SystemError.timedOut
        }
        group.wait()

        lock.lock()
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { throw CancellationError() }

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: out.value, as: UTF8.self),
            stderr: String(decoding: err.value, as: UTF8.self)
        )
    }
}

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
