#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'CosmoOS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.find { |t| t.name == 'CosmoOS' }

# Find or create the UI group
ui_group = project.main_group.children.find { |g| g.display_name == 'UI' }
unless ui_group
  ui_group = project.main_group.new_group('UI')
  puts "Created UI group"
end

# Find or create the FocusMode subgroup
focusmode_group = ui_group.children.find { |g| g.display_name == 'FocusMode' }
unless focusmode_group
  focusmode_group = ui_group.new_group('FocusMode', 'UI/FocusMode')
  puts "Created FocusMode group"
end

# Find or create Research subgroup
research_group = focusmode_group.children.find { |g| g.display_name == 'Research' }
unless research_group
  research_group = focusmode_group.new_group('Research', 'UI/FocusMode/Research')
  puts "Created Research group"
end

# Find or create Connection subgroup
connection_group = focusmode_group.children.find { |g| g.display_name == 'Connection' }
unless connection_group
  connection_group = focusmode_group.new_group('Connection', 'UI/FocusMode/Connection')
  puts "Created Connection group"
end

# Find or create FloatingPanel subgroup
floatingpanel_group = focusmode_group.children.find { |g| g.display_name == 'FloatingPanel' }
unless floatingpanel_group
  floatingpanel_group = focusmode_group.new_group('FloatingPanel', 'UI/FocusMode/FloatingPanel')
  puts "Created FloatingPanel group"
end

def add_file(group, file_path, target)
  file_name = File.basename(file_path)

  # Check if file already exists in group
  existing = group.files.find { |f| f.path&.end_with?(file_name) }
  if existing
    puts "File already exists: #{file_name}"
    return
  end

  # Add file reference
  file_ref = group.new_file(file_path)

  # Add to target's sources build phase
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{file_path}"
end

# Add InfiniteCanvasView to FocusMode group
add_file(focusmode_group, 'UI/FocusMode/InfiniteCanvasView.swift', target)

# Add Research files
research_files = [
  'UI/FocusMode/Research/ResearchFocusModeView.swift',
  'UI/FocusMode/Research/ResearchFocusModeState.swift',
  'UI/FocusMode/Research/ResearchCoreView.swift',
  'UI/FocusMode/Research/TranscriptSpineView.swift'
]

research_files.each do |file|
  add_file(research_group, file, target)
end

# Add Connection files
connection_files = [
  'UI/FocusMode/Connection/ConnectionFocusModeView.swift',
  'UI/FocusMode/Connection/ConnectionFocusModeState.swift',
  'UI/FocusMode/Connection/ConnectionSectionView.swift'
]

connection_files.each do |file|
  add_file(connection_group, file, target)
end

# Add FloatingPanel files
floatingpanel_files = [
  'UI/FocusMode/FloatingPanel/FloatingPanelView.swift',
  'UI/FocusMode/FloatingPanel/FloatingPanelState.swift',
  'UI/FocusMode/FloatingPanel/FloatingPanelManager.swift'
]

floatingpanel_files.each do |file|
  add_file(floatingpanel_group, file, target)
end

project.save
puts "Project saved successfully!"
