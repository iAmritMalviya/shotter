import AppKit
import Carbon.HIToolbox
import os

/// Diagnostics for failures that only happen in real use.
///
/// Read them back with:
///
///     /usr/bin/log show --last 1h --info --predicate 'subsystem == "com.amrit.Shotter"' --style compact
///     /usr/bin/log stream --level debug --predicate 'subsystem == "com.amrit.Shotter"'
///
/// Use the full path: in zsh `log` is a shell builtin, and the bare command fails with "too many
/// arguments" instead of reaching the logging tool.
///
/// Why `os.Logger` and not `print`: stdout is block-buffered when it is not a TTY, so `print`
/// output from the installed app only appears when the process exits. A hung or misbehaving
/// long-running app is exactly when that output is needed.
///
/// Why `.notice` for the events that matter: `.info` and `.debug` are memory-only and are gone
/// by the time anyone runs `log show` after a failure; `.notice` (the default level) is
/// persisted. Everything here is one line per user action, never per mouse move.
///
/// Dynamic strings are redacted to `<private>` in `log show` unless interpolated with
/// `privacy: .public`. Nothing logged here is sensitive — screen names, frames, app names,
/// error text — so those are marked public; without that the logs would be useless.
enum Log {
    private static let subsystem = "com.amrit.Shotter"

    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let permission = Logger(subsystem: subsystem, category: "permission")
    static let system = Logger(subsystem: subsystem, category: "system")
}

extension NSScreen {
    /// `name frame scale`, for log lines.
    var logDescription: String {
        "\(localizedName) \(NSStringFromRect(frame)) @\(backingScaleFactor)x"
    }
}

/// Which screen holds the pointer (AppKit global coordinates).
func screenName(containing point: NSPoint) -> String {
    NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }?.localizedName ?? "none"
}

func frontmostAppName() -> String {
    NSWorkspace.shared.frontmostApplication?.localizedName ?? "none"
}

/// Watches Secure Event Input and logs only when it changes.
///
/// While any process holds Secure Event Input — a focused password field, or a terminal with
/// "Secure Keyboard Entry" on — macOS withholds keystrokes from everything but the focused app,
/// which can keep a Carbon global hotkey from firing at all. That is an intermittent "the hotkey
/// does nothing" with no error anywhere, so it is worth being able to correlate against.
///
/// The PID the session reports is not always the process that enabled it (it reported the
/// frontmost app when another process enabled it), so it is logged as a hint, not an accusation.
@MainActor
final class SecureInputMonitor {
    private var timer: DispatchSourceTimer?
    private var lastState: Bool?

    func start() {
        check()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 10, repeating: 10, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.resume()
        self.timer = timer
    }

    private func check() {
        let enabled = IsSecureEventInputEnabled()
        guard enabled != lastState else { return }
        lastState = enabled

        let pid = (CGSessionCopyCurrentDictionary() as? [String: Any])?["kCGSSessionSecureInputPID"] as? Int
        let name = pid.flatMap { NSRunningApplication(processIdentifier: pid_t($0))?.localizedName } ?? "unknown"
        Log.system.notice("secure event input \(enabled ? "ENABLED" : "disabled", privacy: .public) pid=\(pid ?? 0) app=\(name, privacy: .public) frontmost=\(frontmostAppName(), privacy: .public)")
    }
}
