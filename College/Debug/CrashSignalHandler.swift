#if os(macOS)
import Darwin

private let kHandledSignals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
nonisolated(unsafe) private var gCrashLogPath: UnsafeMutablePointer<CChar>?
nonisolated(unsafe) private var gPreviousHandlers: [Int32: sig_t] = [:]
nonisolated(unsafe) private var gSignalHandlerInstalled = false

enum CrashSignalHandler {
    static func installIfNeeded(logPath: String) {
        guard !gSignalHandlerInstalled else { return }
        gSignalHandlerInstalled = true

        if let existing = gCrashLogPath {
            free(existing)
            gCrashLogPath = nil
        }
        gCrashLogPath = strdup(logPath)

        for sig in kHandledSignals {
            let old = signal(sig, crash_signal_handler)
            gPreviousHandlers[sig] = old
        }
    }
}

private func messageForSignal(_ sig: Int32) -> StaticString {
    switch sig {
    case SIGABRT: return "fatal_signal=SIGABRT\n"
    case SIGSEGV: return "fatal_signal=SIGSEGV\n"
    case SIGBUS: return "fatal_signal=SIGBUS\n"
    case SIGILL: return "fatal_signal=SIGILL\n"
    case SIGFPE: return "fatal_signal=SIGFPE\n"
    case SIGTRAP: return "fatal_signal=SIGTRAP\n"
    default: return "fatal_signal=UNKNOWN\n"
    }
}

private let crash_signal_handler: @convention(c) (Int32) -> Void = { sig in
    guard let path = gCrashLogPath else {
        _exit(sig)
    }

    let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
    if fd >= 0 {
        let header = "Crash signal report\n"
        _ = header.withCString { ptr in
            write(fd, ptr, strlen(ptr))
        }

        let message = messageForSignal(sig)
        _ = withUnsafePointer(to: message.utf8Start) { ptr in
            write(fd, ptr, message.utf8CodeUnitCount)
        }

        close(fd)
    }

    if let previous = gPreviousHandlers[sig] {
        _ = signal(sig, previous)
        raise(sig)
    }

    _exit(sig)
}
#endif
