public protocol FocusPreserver: AnyObject {
    func rememberTarget()
    func restoreTarget()
}

public final class NoopFocusPreserver: FocusPreserver {
    public init() {}
    public func rememberTarget() {}
    public func restoreTarget() {}
}
