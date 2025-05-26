import Foundation

// MARK: - Progress Update Coordinator

/// Coordinates efficient progress updates to prevent UI blocking
class ProgressUpdateCoordinator {

    /// Minimum interval between progress updates (in seconds)
    private let updateInterval: TimeInterval = 0.1 // 100ms

    /// Last update time
    private var lastUpdateTime: Date = Date.distantPast

    /// Pending progress update
    private var pendingUpdate: (() -> Void)?

    /// Update queue for coordinating progress updates
    private let updateQueue = DispatchQueue(label: "com.swiftnote.sync.progress.coordinator", qos: .utility)

    /// Schedule a progress update with throttling
    /// - Parameter update: The update closure to execute
    func scheduleUpdate(_ update: @escaping () -> Void) {
        updateQueue.async { [weak self] in
            guard let self = self else { return }

            let now = Date()
            let timeSinceLastUpdate = now.timeIntervalSince(self.lastUpdateTime)

            // Store the pending update
            self.pendingUpdate = update

            if timeSinceLastUpdate >= self.updateInterval {
                // Execute immediately if enough time has passed
                self.executeUpdate()
            } else {
                // Schedule for later execution
                let delay = self.updateInterval - timeSinceLastUpdate
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.updateQueue.async {
                        self.executeUpdate()
                    }
                }
            }
        }
    }

    /// Execute the pending update
    private func executeUpdate() {
        guard let update = pendingUpdate else { return }

        lastUpdateTime = Date()
        pendingUpdate = nil

        DispatchQueue.main.async {
            update()
        }
    }

    /// Force execute any pending update immediately
    func flushPendingUpdate() {
        updateQueue.async { [weak self] in
            self?.executeUpdate()
        }
    }
}
