# Uncomment the next line to define a global platform for your project
platform :ios, '16.0'

# Ensure all pods support iOS 16.0 and suppress specific warnings
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      
      # Suppress deprecation warnings for pods
      config.build_settings['GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS'] = 'NO'
      config.build_settings['CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS'] = 'NO'
      config.build_settings['CLANG_WARN_DEPRECATED_IMPLEMENTATIONS'] = 'NO'
      
      # Suppress other warnings from pods
      config.build_settings['CLANG_WARN_DOCUMENTATION_COMMENTS'] = 'NO'
      config.build_settings['GCC_WARN_INHIBIT_ALL_WARNINGS'] = 'YES'
      
      # Suppress Swift Sendable warnings
      config.build_settings['SWIFT_SUPPRESS_WARNINGS'] = 'YES'
      config.build_settings['OTHER_SWIFT_FLAGS'] = '$(inherited) -suppress-warnings'
      config.build_settings['SWIFT_STRICT_CONCURRENCY'] = 'minimal'
    end
  end
end

target 'SwiftNote AI' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for SwiftNote AI
  pod 'GoogleSignIn'
  pod 'GoogleAPIClientForREST/YouTube', '~> 3.0'  # Using version 3.0 for better compatibility

end
