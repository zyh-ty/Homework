import AppKit
import Foundation

// 无界面出图模式：`HomeworkMac --export out.png [--date ...] [--mode all|submit] [--data ...]`
if SlideExport.isRequested(CommandLine.arguments) {
    _ = NSApplication.shared
    SlideExport.run(arguments: CommandLine.arguments)
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--page"),
   index + 1 < CommandLine.arguments.count,
   let page = Page(rawValue: CommandLine.arguments[index + 1]) {
    AppState.initialPage = page
}

HomeworkMacApp.main()
