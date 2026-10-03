# Run on macOS from the Flutter project root: ruby tool/install_ios_widget.rb
# Uses the xcodeproj gem supplied with many CocoaPods installations.
require 'xcodeproj'
require 'fileutils'
project_path = 'ios/Runner.xcodeproj'
abort 'Run from your Flutter project root after platform setup.' unless File.directory?(project_path)
project = Xcodeproj::Project.open(project_path)
abort 'SafeVaultWidget already exists. No changes made.' if project.targets.any? { |t| t.name == 'SafeVaultWidget' }
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target missing'
backup = "#{project_path}.before-widget-#{Time.now.to_i}"
FileUtils.cp_r(project_path, backup)
FileUtils.mkdir_p('ios/SafeVaultWidget')
FileUtils.cp_r(Dir['platform_overlays/ios/SafeVaultWidget/*'], 'ios/SafeVaultWidget')
target = project.new_target(:app_extension, 'SafeVaultWidget', :ios, '17.0')
group = project.main_group.new_group('SafeVaultWidget', 'SafeVaultWidget')
target.add_file_references([group.new_file('SafeVaultWidget.swift')])
group.new_file('Info.plist')
target.build_configurations.each do |config|
  parent = runner.build_configurations.find { |c| c.name == config.name } || runner.build_configurations.first
  base = parent.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
  abort 'Runner bundle identifier must be resolved in Xcode first.' if base.nil? || base.include?('$')
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{base}.SafeVaultWidget",
    'INFOPLIST_FILE' => 'SafeVaultWidget/Info.plist',
    'SWIFT_VERSION' => '5.0', 'SKIP_INSTALL' => 'YES',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'CODE_SIGN_STYLE' => 'Automatic',
    'MARKETING_VERSION' => '1.1.0', 'CURRENT_PROJECT_VERSION' => '2',
    'TARGETED_DEVICE_FAMILY' => '1,2'
  })
  team = parent.build_settings['DEVELOPMENT_TEAM']
  config.build_settings['DEVELOPMENT_TEAM'] = team if team
end
runner.add_dependency(target)
embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' } || runner.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
entry = embed.add_file_reference(target.product_reference)
entry.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
project.save
puts "Widget target added. Backup: #{backup}. Open Xcode and select your signing team for both Runner and SafeVaultWidget. Build and test on iOS 17+."
