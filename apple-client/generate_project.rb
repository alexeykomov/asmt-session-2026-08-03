#!/usr/bin/env ruby
# Generate FunWithActivity.xcodeproj with all targets using the xcodeproj gem.
#
# Adapted from cyberfight/apple-client/generate_project.rb (same author,
# house convention: programmatic project generation over a hand-maintained
# pbxproj). Two targets only:
#   FunWithActivityCore — static library. Networking (gRPC client) + models
#     (generated proto messages, provider-status presentation, HealthKit
#     read service) live here per house rule: "Networking and models live
#     in a shared library target; the app target owns only shell
#     composition."
#   FunWithActivity — app target (iPhone). Screens + AppDelegate only.

require 'fileutils'
require 'pathname'
require 'xcodeproj'

PROJECT_DIR = File.dirname(__FILE__)
PROJ_PATH = File.join(PROJECT_DIR, 'FunWithActivity.xcodeproj')

# Optional: apple-client/Config/Generated.xcconfig, produced by
# apple-client/Config/generate-xcconfig.sh from the repo-root .env. It is
# git-ignored build output, not source — this script must tolerate it not
# existing (e.g. on a fresh clone before anyone has run the generator) and
# fall back to FWAServerConfig.h's in-source placeholder defaults.
GENERATED_XCCONFIG_PATH = File.join(PROJECT_DIR, 'Config', 'Generated.xcconfig')

FileUtils.rm_rf(PROJ_PATH)

project = Xcodeproj::Project.new(PROJ_PATH)

# ---------- Helper ----------

def add_files_to_target(project, target, group, dir, extensions: %w[.h .m .c], exclude_pattern: nil)
  compile_exts = %w[.m .c]
  Dir.glob(File.join(dir, '**', '*')).sort.each do |path|
    next unless File.file?(path)
    next if exclude_pattern && path.match?(exclude_pattern)
    ext = File.extname(path)
    next unless extensions.include?(ext)

    rel = Pathname.new(path).relative_path_from(Pathname.new(dir))
    parent_group = group
    rel.dirname.each_filename do |part|
      next if part == '.'
      found = parent_group.children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && g.name == part }
      parent_group = found || parent_group.new_group(part)
    end

    ref = parent_group.new_file(path)
    target.add_file_references([ref]) if compile_exts.include?(ext)
  end
end

def common_build_settings(config, deployment_target: '15.0')
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
  config.build_settings['CLANG_ENABLE_OBJC_ARC'] = 'YES'
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
  config.build_settings['ALWAYS_SEARCH_USER_PATHS'] = 'NO'
  if config.name == 'Release'
    config.build_settings['VALIDATE_PRODUCT'] = 'YES'
    config.build_settings['GCC_OPTIMIZATION_LEVEL'] = 's'
  else
    config.build_settings['GCC_OPTIMIZATION_LEVEL'] = '0'
    config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = ['DEBUG=1', '$(inherited)']
  end
end

# ---------- FunWithActivityCore (static library, iOS) ----------

core_target = project.new_target(:static_library, 'FunWithActivityCore', :ios, '15.0')
core_group = project.main_group.new_group('FunWithActivityCore')
core_dir = File.join(PROJECT_DIR, 'FunWithActivityCore')

add_files_to_target(project, core_target, core_group, core_dir)

# FWAServerConfig.h/.m (in FunWithActivityCore) is driven by
# GCC_PREPROCESSOR_DEFINITIONS. Generated.xcconfig, when present, holds
# FWA_ENV_GRPC_HOST/FWA_ENV_GRPC_TOKEN from the repo-root .env — parse those
# two values out and inject them straight into each build configuration's
# GCC_PREPROCESSOR_DEFINITIONS build setting, rather than setting
# Generated.xcconfig as the target's base_configuration_reference. A target
# has exactly one base-configuration slot, and `pod install` (run after this
# script — see Config/generate-xcconfig.sh's header doc) needs that slot for
# Pods-FunWithActivityCore's own xcconfig (search paths, etc.); claiming it
# here first means CocoaPods silently declines to wire Pods in at all
# ("did not set the base configuration... project already has a custom
# config set"), and every Pod header import fails to resolve. Reading the
# two values out of the file sidesteps the conflict entirely.
generated_defines = nil
if File.exist?(GENERATED_XCCONFIG_PATH)
  xcconfig_contents = File.read(GENERATED_XCCONFIG_PATH)
  env_host = xcconfig_contents[/^FWA_ENV_GRPC_HOST\s*=\s*(.+)$/, 1]&.strip
  env_token = xcconfig_contents[/^FWA_ENV_GRPC_TOKEN\s*=\s*(.+)$/, 1]&.strip
  if env_host && !env_host.empty?
    generated_defines = ["FWA_GRPC_HOST=\\\"#{env_host}\\\""]
    generated_defines << "FWA_GRPC_TOKEN=\\\"#{env_token}\\\"" if env_token && !env_token.empty?
  end
end

core_target.build_configurations.each do |config|
  common_build_settings(config)
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['HEADER_SEARCH_PATHS'] = ['$(inherited)', "#{core_dir}/**"]
  config.build_settings['OTHER_LDFLAGS'] = ['$(inherited)', '-ObjC']
  if generated_defines
    existing_defines = config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] || ['$(inherited)']
    config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = existing_defines + generated_defines
  end
end

# Generated proto sources use manual retain/release (protobuf-objc
# convention) — compile without ARC.
core_target.source_build_phase.files.each do |build_file|
  if build_file.file_ref && build_file.file_ref.path && build_file.file_ref.path.include?('/Generated/')
    build_file.settings = { 'COMPILER_FLAGS' => '-fno-objc-arc' }
  end
end

# ---------- FunWithActivity (iPhone app) ----------

iphone_target = project.new_target(:application, 'FunWithActivity', :ios, '15.0')
iphone_group = project.main_group.new_group('FunWithActivity')
iphone_dir = File.join(PROJECT_DIR, 'FunWithActivity')

add_files_to_target(project, iphone_target, iphone_group, iphone_dir)

# Assets.xcassets — single source of truth for named colours (StatusOK /
# StatusSkipped / StatusDegraded and any future additions). An asset
# catalog is added as one folder reference to the Resources build phase;
# actool reads its contents at build time, so nothing inside it needs its
# own PBXFileReference the way add_files_to_target's .h/.m/.c walk works.
assets_path = File.join(iphone_dir, 'Resources', 'Assets.xcassets')
if Dir.exist?(assets_path)
  resources_group = iphone_group.new_group('Resources')
  assets_ref = resources_group.new_reference(assets_path)
  iphone_target.add_resources([assets_ref])
end

iphone_target.build_configurations.each do |config|
  common_build_settings(config)
  config.build_settings['PRODUCT_NAME'] = 'FunWithActivity'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.funwithactivity.ios'
  config.build_settings['INFOPLIST_FILE'] = '$(SRCROOT)/FunWithActivity/Supporting/Info.plist'
  # No AppIcon/AccentColor set in Assets.xcassets (it exists only for the
  # named status colours) — Xcode's default ASSETCATALOG_COMPILER_*_NAME
  # build settings otherwise point actool at an "AppIcon"/"AccentColor" set
  # that doesn't exist, which is a hard actool error for AppIcon (unlike
  # the accent colour, which only warns).
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = ''
  config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = ''
  config.build_settings['HEADER_SEARCH_PATHS'] = [
    '$(inherited)',
    "#{core_dir}/**",
    "#{iphone_dir}/**",
  ]
  config.build_settings['OTHER_LDFLAGS'] = ['$(inherited)', '-ObjC']
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks'
end

iphone_target.add_dependency(core_target)
iphone_target.frameworks_build_phase.add_file_reference(core_target.product_reference)

# ---------- FunWithActivityCoreTests (logic-only XCTest bundle) ----------
#
# Covers FWAProviderStatusPresentation — the skipped-before-error branch
# order that has already caused three defects on this project. No host app
# needed: it links straight against FunWithActivityCore.

test_target = project.new_target(:unit_test_bundle, 'FunWithActivityCoreTests', :ios, '15.0')
test_group = project.main_group.new_group('FunWithActivityCoreTests')
test_dir = File.join(PROJECT_DIR, 'FunWithActivityCoreTests')

add_files_to_target(project, test_target, test_group, test_dir)

test_target.build_configurations.each do |config|
  common_build_settings(config)
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.funwithactivity.ios.coretests'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['HEADER_SEARCH_PATHS'] = ['$(inherited)', "#{core_dir}/**"]
  config.build_settings['OTHER_LDFLAGS'] = ['$(inherited)', '-ObjC']
end

test_target.add_dependency(core_target)
test_target.frameworks_build_phase.add_file_reference(core_target.product_reference)

# ---------- Save ----------

project.save

# ---------- Shared scheme ----------
#
# xcodeproj doesn't auto-create schemes the way Xcode's UI does. Without
# this, `xcodebuild -scheme FunWithActivity` still builds (xcodebuild
# synthesizes an implicit scheme on the fly), but that implicit scheme has
# no Test action, so `-only-testing:FunWithActivityCoreTests test` fails
# with "Scheme FunWithActivity is not currently configured for the test
# action." Write an explicit shared scheme with both.

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(iphone_target)
scheme.add_build_target(test_target)
scheme.add_test_target(test_target)
scheme.set_launch_target(iphone_target)
scheme.save_as(PROJ_PATH, 'FunWithActivity', true)

puts "Generated #{PROJ_PATH}"
