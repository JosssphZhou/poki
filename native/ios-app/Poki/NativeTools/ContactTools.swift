import Contacts
import Foundation
import PokiCore

/// Finds a contact by name and reads only the display name and phone numbers. A name shared by more
/// than one contact is reported as ambiguous with ids to choose from rather than guessing; limited
/// access is marked in the answer.
enum ContactTools {
    static let specs: [ToolSpec] = [
        .make("contacts_find",
              "Find contacts by name and return display names and phone numbers. With more than one match the answer lists contact_id values and asks the owner which one; call again with contact_id. limited access shows only the contacts shared with Poki.",
              [
                "name": ["type": "string", "description": "A full or partial name."],
                "contact_id": ["type": "string", "description": "A contact_id from an earlier ambiguous answer."],
              ], []),
    ]

    private static let keys: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactMiddleNameKey as CNKeyDescriptor, CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactIdentifierKey as CNKeyDescriptor,
    ]

    private static let store = CNContactStore()

    static func perform(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .denied, .restricted:
            return NativeToolAnswer.permission("Contacts access is not allowed. Open Settings › Privacy & Security › Contacts and allow Poki. Nothing was read.")
        case .notDetermined:
            do {
                let granted = try await requestAccess()
                guard granted else {
                    return NativeToolAnswer.permission("Contacts access was not granted. Nothing was read.")
                }
            } catch {
                return NativeToolAnswer.permission("Contacts access could not be requested: \(error.localizedDescription). Nothing was read.")
            }
        case .authorized, .limited:
            break
        @unknown default:
            return NativeToolAnswer.unavailable("Contacts access state is unknown.")
        }
        if let id = args.string("contact_id") {
            do {
                let contact = try store.unifiedContact(withIdentifier: id, keysToFetch: keys)
                return answer(for: [contact], limited: status == .limited)
            } catch {
                return NativeToolAnswer.empty("no contact has the id \(id); nothing was read.")
            }
        }
        guard let name = args.string("name") else {
            return NativeToolAnswer.invalid("name is required; nothing was read")
        }
        do {
            let predicate = CNContact.predicateForContacts(matchingName: name)
            let found = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            guard !found.isEmpty else {
                return NativeToolAnswer.empty("no contact matches “\(name)”\(status == .limited ? " among the contacts shared with Poki" : "").")
            }
            return answer(for: found, limited: status == .limited)
        } catch {
            return NativeToolAnswer.failed("Contacts could not be searched: \(error.localizedDescription)")
        }
    }

    private static func answer(for contacts: [CNContact], limited: Bool) -> PokiCore.ToolAnswer {
        let normalized = contacts.sorted { displayName($0) < displayName($1) }
        if normalized.count > 1 {
            let lines = normalized.prefix(10).map { contact in
                let phones = contact.phoneNumbers.map { "\($0.label.map(phoneLabel) ?? "phone"): \($0.value.stringValue)" }
                let masked = phones.isEmpty ? "no phone" : phones.joined(separator: ", ")
                return "- \(displayName(contact)) — \(masked) — contact_id \(contact.identifier)"
            }
            let more = normalized.count > 10 ? "\n(only the first 10 are listed)" : ""
            return NativeToolAnswer.ambiguous("more than one contact matches. Ask the owner which one, then call contacts_find with that contact_id; nothing else was done.\n" + lines.joined(separator: "\n") + more)
        }
        let contact = normalized[0]
        let phones = contact.phoneNumbers.map { entry -> String in
            let label = entry.label.map(phoneLabel) ?? "phone"
            return "\(label): \(entry.value.stringValue)"
        }
        guard !phones.isEmpty else {
            return NativeToolAnswer.empty("\(displayName(contact)) has no phone number in the contacts Poki can read.")
        }
        var text = "contact: \(displayName(contact))\n" + phones.joined(separator: "\n")
        if limited { text += "\nlimited access: only contacts shared with Poki are visible." }
        return NativeToolAnswer.ok(text)
    }

    private static func displayName(_ contact: CNContact) -> String {
        let parts = [contact.givenName, contact.middleName, contact.familyName].filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        if !contact.nickname.isEmpty { return contact.nickname }
        if !contact.organizationName.isEmpty { return contact.organizationName }
        return "(unnamed contact)"
    }

    private static func phoneLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "_$!<", with: "").replacingOccurrences(of: ">$_!", with: "")
            .replacingOccurrences(of: "Phone", with: "phone")
            .lowercased()
    }

    private static func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: granted) }
            }
        }
    }
}
