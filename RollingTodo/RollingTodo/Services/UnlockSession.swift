import Foundation
import LocalAuthentication
import Observation

@MainActor
@Observable
final class UnlockSession {
    private var unlockedIDs: Set<UUID> = []

    func isUnlocked(_ noteID: UUID) -> Bool {
        unlockedIDs.contains(noteID)
    }

    func unlock(_ noteID: UUID) {
        unlockedIDs.insert(noteID)
    }

    func lockAll() {
        unlockedIDs.removeAll()
    }

    /// Prompts for device authentication (biometric with passcode fallback).
    /// Returns true on success.
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
