import Foundation

@MainActor
public protocol AudioRecorder: AnyObject {
    func start() throws
    func stop() throws -> URL
    func cancel()
}
