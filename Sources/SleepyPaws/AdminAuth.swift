import Foundation
import OSLog
import Security

/// "Forgot PIN?": macOS asks for the name and password of an administrator of this Mac in its
/// own dialog. A child using a standard account doesn't have them; the app never sees them.
enum AdminAuth {
    private static let log = Logger(subsystem: "pro.lirik.sleepypaws", category: "auth")

    /// Shows the system dialog off the main thread and reports on the main thread.
    static func request(_ reason: String, completion: @escaping @MainActor (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let approved = authenticate(reason)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(approved) } }
        }
    }

    private static func authenticate(_ reason: String) -> Bool {
        var authorization: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess,
              let authorization else { return false }
        defer { AuthorizationFree(authorization, [.destroyRights]) }

        // "system.privilege.admin" needs an administrator's credentials every time.
        let status = kAuthorizationRightExecute.withCString { name -> OSStatus in
            kAuthorizationEnvironmentPrompt.withCString { promptName -> OSStatus in
            reason.withCString { prompt -> OSStatus in
                var right = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
                var promptItem = AuthorizationItem(
                    name: promptName, valueLength: strlen(prompt),
                    value: UnsafeMutableRawPointer(mutating: prompt), flags: 0
                )
                return withUnsafeMutablePointer(to: &right) { rightPointer in
                    withUnsafeMutablePointer(to: &promptItem) { promptPointer in
                        var rights = AuthorizationRights(count: 1, items: rightPointer)
                        var environment = AuthorizationEnvironment(count: 1, items: promptPointer)
                        return AuthorizationCopyRights(
                            authorization, &rights, &environment,
                            [.interactionAllowed, .extendRights, .destroyRights], nil
                        )
                    }
                }
            }
            }
        }
        if status != errAuthorizationSuccess && status != errAuthorizationCanceled {
            log.error("Administrator check failed: \(status, privacy: .public)")
        }
        return status == errAuthorizationSuccess
    }
}
