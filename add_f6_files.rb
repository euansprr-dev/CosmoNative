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

# --- UI/FocusMode group ---
ui_group = project.main_group.children.find { |g| g.display_name == 'UI' }
if ui_group
  focus_mode_group = ui_group.children.find { |g| g.display_name == 'FocusMode' }
  if focus_mode_group
    add_file_with_absolute_path(focus_mode_group, 'UI/FocusMode/FocusConnectManager.swift', target)
    add_file_with_absolute_path(focus_mode_group, 'UI/FocusMode/FocusConnectionLinesLayer.swift', target)
  else
    puts "Warning: Could not find FocusMode group"
  end
else
  puts "Warning: Could not find UI group"
end

project.save
puts "Project saved successfully"
