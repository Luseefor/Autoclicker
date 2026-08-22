import Foundation
import AutomaterKit

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--version" || args.isEmpty {
    print("automater-cli 0.1.0 (swift-rewrite)")
    exit(0)
}

print("Unknown command: \(args.joined(separator: " "))")
print("Usage: automater-cli [--version]")
exit(2)
