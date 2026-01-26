import ContactsUI
import AppKit

func test() {
    let picker = CNContactPicker()
    picker.showRelativeToRect(.zero, ofView: NSView(), preferredEdge: .maxY)
}
