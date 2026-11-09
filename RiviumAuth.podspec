Pod::Spec.new do |s|
  s.name             = 'RiviumAuth'
  s.version          = '0.4.0'
  s.summary          = 'Sign-in for iOS apps: anonymous, Apple, Google, e-mail, magic link and Telegram'
  s.description      = 'Rivium Auth client for iOS and macOS. Signs users in, keeps the session in the Keychain, refreshes the access token before it expires and hands it to the other Rivium SDKs through a token provider.'
  s.homepage         = 'https://rivium.co'
  s.documentation_url = 'https://rivium.co/cloud/rivium-auth/docs/sdks-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Rivium' => 'support@rivium.co' }
  s.source           = { :git => 'https://github.com/Rivium-co/rivium_auth_ios_sdk.git', :tag => '0.4.0' }

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '12.0'
  s.swift_version = '5.7'

  s.source_files = 'Sources/**/*.swift'
  s.frameworks = 'Foundation', 'Security', 'CryptoKit', 'AuthenticationServices'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
