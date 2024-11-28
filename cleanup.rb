require 'xcodeproj'

project_path = 'SwiftNote AI.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Remove pod configurations
project.targets.each do |target|
  target.build_phases.each do |phase|
    if phase.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase) && phase.name&.include?('[CP]')
      target.build_phases.delete(phase)
    end
  end

  # Remove pod configurations from build settings
  target.build_configurations.each do |config|
    config.build_settings.delete('PODS_PODFILE_DIR_PATH')
    config.build_settings.delete('PODS_ROOT')
    config.build_settings.delete('PODS_BUILD_DIR')
    config.build_settings.delete('PODS_CONFIGURATION_BUILD_DIR')
    config.build_settings.delete('PODS_XCFRAMEWORKS_BUILD_DIR')
    config.build_settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'YES'
  end
end

project.save
