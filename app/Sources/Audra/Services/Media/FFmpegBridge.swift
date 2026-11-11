import Foundation

/// Optional bridge used only for containers AVFoundation cannot read (MKV, WebM, AVI…).
/// It never runs for MP4/MOV/M4V, which are decoded natively with hardware acceleration.
enum FFmpegBridge {
    static var executable: URL? {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        return candidates.lazy.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var isAvailable: Bool { executable != nil }

    /// Remuxes `input` into an MP4 that AVFoundation can play. Video is stream-copied when possible,
    /// otherwise re-encoded with VideoToolbox (hardware). Audio is converted to AAC.
    static func makePlayableProxy(from input: URL, to output: URL) async throws {
        guard let ffmpeg = executable else { throw MediaError.unsupportedContainer(input.pathExtension.uppercased()) }
        try? FileManager.default.removeItem(at: output)

        let copyArgs = ["-hide_banner", "-loglevel", "error", "-y", "-i", input.path,
                        "-map", "0:v:0?", "-map", "0:a:0?", "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
                        "-movflags", "+faststart", output.path]
        if (try? await run(ffmpeg, copyArgs)) != nil, FileManager.default.fileExists(atPath: output.path) { return }

        let encodeArgs = ["-hide_banner", "-loglevel", "error", "-y", "-i", input.path,
                          "-map", "0:v:0?", "-map", "0:a:0?", "-c:v", "h264_videotoolbox", "-b:v", "4M",
                          "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", output.path]
        try await run(ffmpeg, encodeArgs)
    }

    private static func run(_ executable: URL, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { proc in
                    if proc.terminationStatus == 0 {
                        cont.resume()
                    } else if proc.terminationReason == .uncaughtSignal {
                        cont.resume(throwing: CancellationError())
                    } else {
                        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        cont.resume(throwing: MediaError.conversionFailed(String(message.suffix(300))))
                    }
                }
                do { try process.run() } catch { cont.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
