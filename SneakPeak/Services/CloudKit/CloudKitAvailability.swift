//
//  CloudKitAvailability.swift
//  SneakPeak
//
//  Detects whether the app was signed with the iCloud container entitlement.
//

import Foundation
import Security

/// Sideloaded installs (AltStore, SideStore, Sideloadly, …) are re-signed by a
/// team that cannot register `iCloud.com.alzimerahmed.SneakPeak` (container IDs are
/// globally unique), so the iCloud entitlements are stripped or remapped.
/// `CKContainer(identifier:)` fatally traps in that state, so the container
/// must never be created when the entitlement is missing.
enum CloudKitAvailability {
    /// Whether CloudKit APIs may be used in this installation.
    ///
    /// Determined by parsing the embedded provisioning profile. Builds without
    /// an embedded profile (App Store, TestFlight, simulator) always carry the
    /// correct entitlements and are treated as available.
    static let isAvailable: Bool = {
        guard let entitlements = embeddedProvisioningEntitlements() else {
            // No embedded profile: verify the task's actual signing
            // entitlements instead of assuming they are present. Ad-hoc or
            // unsigned builds (CI test hosts) carry none and would trap in
            // CKContainer(identifier:) if we assumed availability.
            return taskEntitledContainers().contains(AppIdentifiers.iCloudContainer)
        }
        let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
        return containers.contains(AppIdentifiers.iCloudContainer)
    }()

    /// Reads the process's signing entitlements for the iCloud container
    /// identifier list, independent of provisioning profiles.
    private static func taskEntitledContainers() -> [String] {
        var error: Unmanaged<CFError>?
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValuesForEntitlements(
                  task,
                  ["com.apple.developer.icloud-container-identifiers"] as CFArray,
                  &error
              )
        else { return [] }
        return value["com.apple.developer.icloud-container-identifiers" as CFString] as? [String] ?? []
    }

    /// Extracts the entitlements dictionary from the embedded provisioning
    /// profile — a CMS blob wrapping an XML property list.
    private static func embeddedProvisioningEntitlements() -> [String: Any]? {
        #if os(macOS)
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile")
        #else
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") else { return nil }
        let url = URL(fileURLWithPath: path)
        #endif

        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound),
                  format: nil
              ),
              let profile = plist as? [String: Any]
        else { return nil }

        return profile["Entitlements"] as? [String: Any]
    }
}
