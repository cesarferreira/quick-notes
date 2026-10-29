import AppKit
import Darwin

func runApplication() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}

let request = AppRequest(arguments: CommandLine.arguments)
let existingApp = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.cesar.quicknotes")
    .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }

if request == .toggle && ProcessInfo.processInfo.environment["QUICK_NOTES_DIRECTORY"] == nil {
    if existingApp {
        if !request.send() {
            fputs("Quick Notes did not acknowledge the toggle request.\n", stderr)
            exit(1)
        }
    } else if Bundle.main.bundleURL.pathExtension == "app" {
        // Launch a separate GUI process so kiwi's command worker can return.
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = ["-n", "-a", Bundle.main.bundleURL.path]
        do {
            try launcher.run()
            launcher.waitUntilExit()
            exit(launcher.terminationStatus)
        } catch {
            fputs("Could not launch Quick Notes: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    } else {
        runApplication()
    }
} else {
    runApplication()
}
