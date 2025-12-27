#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'CosmoOS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.find { |t| t.name == 'CosmoOS' }

# Remove the broken UI/FocusMode group if it exists
ui_group = project.main_group.children.find { |g| g.display_name == 'UI' }
if ui_group
  focusmode_group = ui_group.children.find { |g| g.display_name == 'FocusMode' }
  if focusmode_group
    # Remove all file references from build phases first
    focusmode_group.recursive_children.each do |child|
      if child.is_a?(Xcodeproj::Project::Object::PBXFileReference)
        target.source_build_phase.files.each do |build_file|
          if build_file.file_ref == child
            target.source_build_phase.files.delete(build_file)
          end
        end
      end
    end
    focusmode_group.remove_from_project
    puts "Removed broken FocusMode group"
  end
end

# Find or create the Focus group (where FocusCanvasView.swift is)
focus_group = project.main_group.children.find { |g| g.display_name == 'Focus' }
unless focus_group
  puts "Focus group not found, creating..."
  focus_group = project.main_group.new_group('Focus', 'Focus')
end

def add_file_to_group(group, full_path, target)
  file_name = File.basename(full_path)

  # Check if file already exists in group
  existing = group.files.find { |f| f.display_name == file_name }
  if existing
    puts "File already exists: #{file_name}"
    return
  end

  # Add file reference with just the filename (relative to group path)
  file_ref = group.new_reference(full_path)
  file_ref.source_tree = 'SOURCE_ROOT'

  # Add to target's sources build phase
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{file_name}"
end

# Create FocusMode subgroup under Focus
focusmode_group = focus_group.children.find { |g| g.display_name == 'FocusMode' }
unless focusmode_group
  focusmode_group = focus_group.new_group('FocusMode')
  puts "Created FocusMode subgroup"
end

# Create Research subgroup
research_group = focusmode_group.children.find { |g| g.display_name == 'Research' }
unless research_group
  research_group = focusmode_group.new_group('Research')
  puts "Created Research subgroup"
end

# Create Connection subgroup
connection_group = focusmode_group.children.find { |g| g.display_name == 'Connection' }
unless connection_group
  connection_group = focusmode_group.new_group('Connection')
  puts "Created Connection subgroup"
end

# Create FloatingPanel subgroup
floatingpanel_group = focusmode_group.children.find { |g| g.display_name == 'FloatingPanel' }
unless floatingpanel_group
  floatingpanel_group = focusmode_group.new_group('FloatingPanel')
  puts "Created FloatingPanel subgroup"
end

# Add InfiniteCanvasView
add_file_to_group(focusmode_group, 'UI/FocusMode/InfiniteCanvasView.swift', target)

# Add Research files
['ResearchFocusModeView.swift', 'ResearchFocusModeState.swift', 'ResearchCoreView.swift', 'TranscriptSpineView.swift'].each do |file|
  add_file_to_group(research_group, "UI/FocusMode/Research/#{file}", target)
end

# Add Connection files
['ConnectionFocusModeView.swift', 'ConnectionFocusModeState.swift', 'ConnectionSectionView.swift'].each do |file|
  add_file_to_group(connection_group, "UI/FocusMode/Connection/#{file}", target)
end

# Add FloatingPanel files
['FloatingPanelView.swift', 'FloatingPanelState.swift', 'FloatingPanelManager.swift'].each do |file|
  add_file_to_group(floatingpanel_group, "UI/FocusMode/FloatingPanel/#{file}", target)
end

project.save
puts "Project saved successfully!"
