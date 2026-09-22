import AppKit

@main
struct MenuChecks {
    @MainActor static func main() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        assert(CapsuleController.isMenuBarBounds(CGRect(x: 0, y: 0, width: 1440, height: 24), display: display))
        assert(CapsuleController.isMenuBarBounds(CGRect(x: 0, y: -18, width: 1440, height: 24), display: display))
        assert(!CapsuleController.isMenuBarBounds(CGRect(x: 0, y: -24, width: 1440, height: 24), display: display))
        assert(!CapsuleController.isMenuBarBounds(CGRect(x: 0, y: 0, width: 300, height: 24), display: display))
        assert(!CapsuleController.isMenuBarBounds(CGRect(x: 0, y: 60, width: 1440, height: 24), display: display))
        assert(!CapsuleController.isMenuBarBounds(CGRect(x: 1440, y: 0, width: 1920, height: 24), display: display))
        let second = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        assert(CapsuleController.isMenuBarBounds(CGRect(x: -1920, y: -100, width: 1920, height: 24), display: second))
        print("PASS menu visible, entering, hidden, unrelated windows and multiple-display coordinates")
    }
}
