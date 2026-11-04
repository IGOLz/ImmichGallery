import Foundation

@main struct PasswordBannerChecks {
    static func main() throws {
        for admin: Bool? in [true, false, nil] {
            for change: Bool? in [true, false, nil] {
                for enabled in [true, false] {
                    var payload: [String: Any] = ["id": "test", "email": "test@example.invalid", "name": "Test"]
                    if let admin { payload["isAdmin"] = admin }
                    if let change { payload["shouldChangePassword"] = change }
                    let user = try JSONDecoder().decode(User.self, from: JSONSerialization.data(withJSONObject: payload))
                    let expected = enabled && admin != true && change == true
                    precondition(user.requiresPasswordChange(passwordLoginEnabled: enabled) == expected)
                }
            }
        }
        print("Password banner checks passed: admin, password login and optional flag combinations.")
    }
}
