#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'CosmoOS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.find { |t| t.name == 'CosmoOS' }

# Find UI group
ui_group = project.main_group.children.find { |g| g.display_name == 'UI' }
unless ui_group
  puts "UI group not found!"
  exit 1
end

# Remove bad CommandK group if it exists
bad_commandk = ui_group.children.find { |g| g.display_name == 'CommandK' }
if bad_commandk
  # Remove files from build phase
  bad_commandk.files.each do |file_ref|
    target.source_build_phase.files.each do |build_file|
      if build_file.file_ref == file_ref
        target.source_build_phase.files.delete(build_file)
        puts "Removed from build phase: #{file_ref.path}"
      end
    end
  end
  bad_commandk.remove_from_project
  puts "Removed bad CommandK group"
end

# Create correct CommandK group with proper path
commandk_group = ui_group.new_group('CommandK')
commandk_group.set_source_tree('SOURCE_ROOT')
commandk_group.set_path('UI/CommandK')

# Add files with correct paths
files_to_add = [
  { name: 'CommandKViewModel.swift', path: 'UI/CommandK/CommandKViewModel.swift' },
  { name: 'CommandKView.swift', path: 'UI/CommandK/CommandKView.swift' }
]

files_to_add.each do |file_info|
  file_ref = commandk_group.new_reference(file_info[:name])
  file_ref.set_source_tree('SOURCE_ROOT')
  file_ref.set_path(file_info[:path])
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{file_info[:path]}"
end

project.save
puts "Project saved successfully!"
