import Foundation

/// Connecting a service is a button in Settings that opens a normal browser consent
/// screen — no tokens, no dotfiles, nothing for the user to copy. Illusory's own
/// client secrets stay on illusory.fulmina.re, because a distributed Mac app cannot
/// keep a secret and should not be asked to.
enum Integrations {
    static let enabled = true
}
