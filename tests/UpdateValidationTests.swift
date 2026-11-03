import Foundation

@main struct UpdateValidationTests {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let target = URL(fileURLWithPath: CommandLine.arguments[2])
        do {
            let manifest = try validateUpdate(directory, target: target)
            print("accepted " + manifest["release_tag"]!)
        } catch {
            fputs(error.localizedDescription + "\n", stderr)
            exit(1)
        }
    }
}
