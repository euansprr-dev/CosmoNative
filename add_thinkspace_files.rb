#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'CosmoOS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.find { |t| t.name == 'CosmoOS' }

# Find the Canvas group
canvas_group = project.main_group.children.find { |g| g.display_name == 'Canvas' }
unless canvas_group
  puts "Canvas group not found!"
  exit 1
end

# Files to add to Canvas group
files_to_add = [
  'ThinkspaceManager.swift',
  'ThinkspaceSidebar.swift'
]

files_to_add.each do |file_name|
  # Check if file already exists in group
  existing = canvas_group.files.find { |f| f.path&.end_with?(file_name) }
  if existing
    puts "File already exists: #{file_name}"
    next
  end

  # Add file reference
  file_ref = canvas_group.new_file(file_name)

  # Add to target's sources build phase
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{file_name}"
end

project.save
puts "Project saved successfully!"
