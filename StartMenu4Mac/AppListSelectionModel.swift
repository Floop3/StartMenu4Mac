import Foundation

struct AppListSelectionModel {
    static func clearSelectionsForModeChange(appSelection: inout Int?, recentSelection: inout Int?) {
        appSelection = nil
        recentSelection = nil
    }

    static func movedIndex(current: Int?, direction: Int, itemCount: Int) -> Int? {
        guard itemCount > 0, direction == -1 || direction == 1 else { return nil }
        let startingIndex = current ?? (direction > 0 ? -1 : itemCount)
        return min(max(startingIndex + direction, 0), itemCount - 1)
    }

    static func reconciledIndex<ID: Equatable>(current: Int?, previousIDs: [ID], currentIDs: [ID]) -> Int? {
        guard let current, previousIDs.indices.contains(current) else { return nil }
        return currentIDs.firstIndex(of: previousIDs[current])
    }

    static func itemToActivate<Item>(explicitItem: Item?, selectedIndex: Int?, items: [Item]) -> Item? {
        if let explicitItem { return explicitItem }
        guard let selectedIndex, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }
}

struct PointerHoverSelectionGate: Equatable {
    private(set) var allowsHoverSelection = false

    mutating func notePointerMovement() {
        allowsHoverSelection = true
    }

    mutating func noteKeyboardSelection() {
        allowsHoverSelection = false
    }

    mutating func reset() {
        allowsHoverSelection = false
    }
}
