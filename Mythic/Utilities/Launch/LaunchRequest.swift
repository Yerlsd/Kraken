import Foundation

struct LaunchRequest: Sendable, Equatable {
    let executableURL: URL
    let arguments: [String]
    let container: ContainerReference?
    let runtimeID: RuntimeID
}
