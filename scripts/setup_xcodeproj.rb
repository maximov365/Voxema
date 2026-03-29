#!/usr/bin/env ruby
# FIX-1: Wire all source files into Voxema.xcodeproj, fix build settings
# Run from the repository root: ruby scripts/setup_xcodeproj.rb

require 'xcodeproj'
require 'pathname'

PROJECT_PATH = File.expand_path('../Voxema.xcodeproj', __FILE__)
ROOT = File.expand_path('..', __FILE__)

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == 'Voxema' }
raise "Target 'Voxema' not found" unless target

# ── 1. Fix build settings ──────────────────────────────────────────────────
project.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
end

target.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Voxema/Voxema.entitlements'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.voxema.Voxema'
  config.build_settings['INFOPLIST_FILE'] = 'Voxema/Info.plist'
end

# ── 2. Helper: find or create group ───────────────────────────────────────
def find_or_create_group(parent, name, path = nil)
  existing = parent.children.find { |c| c.respond_to?(:name) && c.name == name }
  return existing if existing
  group = parent.new_group(name, path || name)
  group
end

# ── 3. Source file map: group path → filesystem glob ──────────────────────
# Each entry: [xcode group path (array), filesystem path relative to ROOT]
SOURCES = {
  ['Voxema', 'App']                           => 'Voxema/App',
  ['Voxema', 'Pipeline', 'Coordinator']       => 'Voxema/Pipeline/Coordinator',
  ['Voxema', 'Pipeline', 'Capture']           => 'Voxema/Pipeline/Capture',
  ['Voxema', 'Pipeline', 'Transcribe']        => 'Voxema/Pipeline/Transcribe',
  ['Voxema', 'Pipeline', 'Diarize']           => 'Voxema/Pipeline/Diarize',
  ['Voxema', 'Pipeline', 'Summarize']         => 'Voxema/Pipeline/Summarize',
  ['Voxema', 'Pipeline', 'Export']            => 'Voxema/Pipeline/Export',
  ['Voxema', 'Core', 'Models']                => 'Voxema/Core/Models',
  ['Voxema', 'Core', 'Storage']               => 'Voxema/Core/Storage',
  ['Voxema', 'Core', 'Security']              => 'Voxema/Core/Security',
  ['Voxema', 'Core', 'ModelManager']          => 'Voxema/Core/ModelManager',
  ['Voxema', 'Core', 'Networking']            => 'Voxema/Core/Networking',
  ['Voxema', 'Core', 'LicenseManager']        => 'Voxema/Core/LicenseManager',
  ['Voxema', 'Core', 'UpdateManager']         => 'Voxema/Core/UpdateManager',
  ['Voxema', 'Core', 'Logging']               => 'Voxema/Core/Logging',
  ['Voxema', 'Features', 'Recording']         => 'Voxema/Features/Recording',
  ['Voxema', 'Features', 'MeetingLibrary']    => 'Voxema/Features/MeetingLibrary',
  ['Voxema', 'Features', 'MeetingDetail']     => 'Voxema/Features/MeetingDetail',
  ['Voxema', 'Features', 'Settings']          => 'Voxema/Features/Settings',
  ['Voxema', 'Features', 'Onboarding']        => 'Voxema/Features/Onboarding',
}

# ── 4. Build group hierarchy and add .swift files ─────────────────────────
files_added = 0

SOURCES.each do |group_path, fs_path|
  # Navigate/create group hierarchy
  current_group = project.main_group
  group_path.each do |segment|
    child = current_group.children.find { |c| c.respond_to?(:name) && c.name == segment }
    if child
      current_group = child
    else
      current_group = current_group.new_group(segment, segment)
    end
  end

  # Add .swift files in this directory
  full_dir = File.join(ROOT, fs_path)
  next unless File.directory?(full_dir)

  Dir.glob(File.join(full_dir, '*.swift')).each do |swift_file|
    filename = File.basename(swift_file)
    already = current_group.children.find { |c| c.respond_to?(:path) && c.path == filename }
    next if already

    file_ref = current_group.new_file(swift_file)
    file_ref.source_tree = '<group>'
    file_ref.path = filename

    target.source_build_phase.add_file_reference(file_ref)
    files_added += 1
    puts "  + #{group_path.join('/')}/#{filename}"
  end
end

# ── 5. Add entitlements and Info.plist as references (not compiled) ────────
support_group = project.main_group.children.find { |c| c.respond_to?(:name) && c.name == 'Voxema' } ||
                project.main_group.new_group('Voxema', 'Voxema')

['Voxema.entitlements', 'Info.plist'].each do |filename|
  already = support_group.children.find { |c| c.respond_to?(:path) && c.path == filename }
  unless already
    ref = support_group.new_file(File.join(ROOT, 'Voxema', filename))
    ref.source_tree = '<group>'
    ref.path = filename
    puts "  + Voxema/#{filename} (resource ref)"
  end
end

# ── 6. Save ────────────────────────────────────────────────────────────────
project.save
puts "\nDone. #{files_added} Swift files added to Voxema target."
puts "Build settings updated: MACOSX_DEPLOYMENT_TARGET=13.0, ENABLE_HARDENED_RUNTIME=YES, CODE_SIGN_ENTITLEMENTS set."
