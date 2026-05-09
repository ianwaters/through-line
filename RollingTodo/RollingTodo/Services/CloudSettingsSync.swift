import Foundation

/// Mirrors a fixed set of UserDefaults keys to NSUbiquitousKeyValueStore so app
/// preferences sync across the user's devices via iCloud's tiny (1MB) key-value
/// store — separate from the CloudKit container that holds note data.
///
/// Bidirectional: cloud → local on launch and on external change notifications,
/// local → cloud whenever UserDefaults values shift. Uses value comparison rather
/// than a flag to break the cycle (no infinite loop because writes that don't
/// change the value never fire either notification).
@MainActor
final class CloudSettingsSync {
    static let shared = CloudSettingsSync()

    /// The defaults keys that get mirrored to the cloud key-value store.
    /// Per-device state (focusModeEnabled, inspectorVisible, quickCaptureFolderID,
    /// noteSort.*) is intentionally excluded.
    private let syncedKeys: Set<String> = [
        "showHomepageNote",
        "autoRescheduleOverdue",
        "dueTodayIsUrgent",
        "autoArchiveEnabled",
        "autoArchiveAge",
        "focusDueWindow",
        "focusPriorityFloor"
    ]

    private let store = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    private var observers: [NSObjectProtocol] = []
    private var started = false

    private init() {}

    /// Idempotent — safe to call from .onAppear which can fire multiple times.
    func start() {
        guard !started else { return }
        started = true

        // Initial pull so the local store reflects whatever the cloud already has.
        pullFromCloud()

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: store,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.pullFromCloud() }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.pushToCloud() }
            }
        )

        // Forces a sync attempt — usually quick, returns false if iCloud is offline.
        store.synchronize()
    }

    private func pullFromCloud() {
        for key in syncedKeys {
            guard let cloudValue = store.object(forKey: key) else { continue }
            let localValue = defaults.object(forKey: key)
            guard !areEqual(localValue, cloudValue) else { continue }
            defaults.set(cloudValue, forKey: key)
        }
    }

    private func pushToCloud() {
        for key in syncedKeys {
            let localValue = defaults.object(forKey: key)
            let cloudValue = store.object(forKey: key)
            guard !areEqual(localValue, cloudValue) else { continue }
            if let localValue {
                store.set(localValue, forKey: key)
            } else {
                store.removeObject(forKey: key)
            }
        }
    }

    /// Loose equality across the property-list types these settings can hold.
    private func areEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (l as Bool, r as Bool): return l == r
        case let (l as String, r as String): return l == r
        case let (l as NSNumber, r as NSNumber): return l == r
        default: return false
        }
    }
}
