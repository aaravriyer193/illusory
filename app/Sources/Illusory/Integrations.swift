import Foundation

/// Integrations are built but deliberately off. Until connecting a service is a
/// button inside the app, the only way to enable one would be editing a dotfile —
/// which is not something a user should ever be asked to do. Flip this when the
/// in-app connect flow lands.
enum Integrations {
    static let enabled = false
}
