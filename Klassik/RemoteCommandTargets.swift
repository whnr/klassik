import MediaPlayer

/// Removes remote-command targets when their session goes away. Without it, a dead session keeps its targets.
final class RemoteCommandTargets {
    private var registered: [(command: MPRemoteCommand, token: Any)] = []

    func add(
        _ command: MPRemoteCommand,
        _ handler: @escaping @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        registered.append((command, command.addTarget(handler: handler)))
    }

    deinit {
        for (command, token) in registered { command.removeTarget(token) }
    }
}
