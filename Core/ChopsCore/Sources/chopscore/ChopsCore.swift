/// ChopsCore — the portable core of Chops for Linux.
///
/// macOS sources under `Chops/**` are frozen (work plan Must-NOT-Have #1): each
/// capability is re-declared here as new Linux-target Swift, ported task-by-task
/// from the frozen originals rather than shared.
///
/// Scaffolding constant only — real logic lands with Batch 1 (GRDB store, parsers,
/// scanner, transports, watcher).
public enum ChopsCore {
    /// Version of the portable Linux core (not the macOS app version).
    public static let version = "0.1.0-dev"
}
