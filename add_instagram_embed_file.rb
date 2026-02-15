#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'CosmoOS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.find { |t| t.name == 'CosmoOS' }

def add_file_with_absolute_path(group, file_path, target)
  file_name = File.basename(file_path)

  # Check if file already exists in group
  existing = group.files.find { |f| File.basename(f.path.to_s) == file_name }
  if existing
    puts "File already exists: #{file_name}"
    return
  end

  # Create file reference with SOURCE_ROOT relative path
  file_ref = group.new_reference(file_path)
  file_ref.source_tree = 'SOURCE_ROOT'
  file_ref.path = file_path

  # Add to target's sources build phase
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{file_path}"
end

# --- UI/FocusMode/SwipeStudy group ---
focus_mode_group = project.main_group.find_subpath('UI/FocusMode') || project.main_group.new_group('UI').new_group('FocusMode')
swipe_study_group = focus_mode_group.find_subpath('SwipeStudy') || focus_mode_group.new_group('SwipeStudy')

add_file_with_absolute_path(swipe_study_group, 'UI/FocusMode/SwipeStudy/InstagramEmbedView.swift', target)

project.save
puts "\nDone! InstagramEmbedView.swift added to Xcode project."
