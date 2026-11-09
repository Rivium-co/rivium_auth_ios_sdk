import Foundation

/// The SDK version. Keep it equal to `s.version` in RiviumAuth.podspec — a test checks it.
let riviumAuthSDKVersion = "0.2.0"

/// Sent as `X-Rivium-SDK` with every request, so Rivium can show which SDK versions are in use.
let riviumAuthSDKHeader = "auth-ios/\(riviumAuthSDKVersion)"
