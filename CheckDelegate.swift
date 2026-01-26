import ContactsUI
import Contacts

class MyDelegate: NSObject, CNContactPickerDelegate {
    func contactPicker(_ picker: CNContactPicker, didSelect contact: CNContact) {}
}
