import Foundation

enum ReloadHelper {
    static func reloadAlacritty() {
        let cmd = """
        ( /opt/homebrew/bin/alacritty msg config reload \
          || /usr/local/bin/alacritty msg config reload \
          || alacritty msg config reload \
          || "/Applications/Alacritty.app/Contents/MacOS/alacritty" msg config reload \
          || killall -USR1 Alacritty \
        ) >/dev/null 2>&1 || true
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", cmd]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
    }
}


