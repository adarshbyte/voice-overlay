public enum ShortcutLabel {
    public static func display(
        key: String,
        control: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        command: Bool = false
    ) -> String {
        var parts = ""
        if control { parts += "⌃" }
        if option { parts += "⌥" }
        if shift { parts += "⇧" }
        if command { parts += "⌘" }
        return parts + key
    }
}
