#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'CosmoOS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.find { |t| t.name == 'CosmoOS' }

# Find or create the UI/CommandK group
ui_group = project.main_group.children.find { |g| g.display_name == 'UI' }
unless ui_group
  puts "UI group not found!"
  exit 1
end

# Create CommandK group if not exists
commandk_group = ui_group.children.find { |g| g.display_name == 'CommandK' }
unless commandk_group
  commandk_group = ui_group.new_group('CommandK', 'UI/CommandK')
end

# Files to add
files_to_add = [
  'UI/CommandK/CommandKViewModel.swift',
  'UI/CommandK/CommandKView.swift'
]

files_to_add.each do |file_path|
  # Check if file already exists in group
  existing = commandk_group.files.find { |f| f.path&.end_with?(File.basename(file_path)) }
  if existing
    puts "File already exists: #{file_path}"
    next
  end
  
  # Add file reference
  file_ref = commandk_group.new_file(File.basename(file_path))
  
  # Add to target's sources build phase
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{file_path}"
end

project.save
puts "Project saved successfully!"
