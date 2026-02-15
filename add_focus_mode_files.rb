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

# --- AI group ---
ai_group = project.main_group.children.find { |g| g.display_name == 'AI' }
if ai_group
  add_file_with_absolute_path(ai_group, 'AI/WritingAnalyzer.swift', target)
  add_file_with_absolute_path(ai_group, 'AI/PolishEngine.swift', target)
else
  puts "Warning: Could not find AI group"
end

# --- UI/FocusMode group ---
ui_group = project.main_group.children.find { |g| g.display_name == 'UI' }
focusmode_group = ui_group&.children&.find { |g| g.display_name == 'FocusMode' }

unless focusmode_group
  puts "Error: Could not find UI/FocusMode group"
  exit 1
end

# --- Notes subgroup ---
notes_group = focusmode_group.children.find { |g| g.display_name == 'Notes' }
unless notes_group
  notes_group = focusmode_group.new_group('Notes')
  notes_group.source_tree = 'SOURCE_ROOT'
  notes_group.path = 'UI/FocusMode/Notes'
  puts "Created Notes group"
end
add_file_with_absolute_path(notes_group, 'UI/FocusMode/Notes/NoteFocusModeView.swift', target)

# --- Content subgroup ---
content_group = focusmode_group.children.find { |g| g.display_name == 'Content' }
unless content_group
  content_group = focusmode_group.new_group('Content')
  content_group.source_tree = 'SOURCE_ROOT'
  content_group.path = 'UI/FocusMode/Content'
  puts "Created Content group"
end

content_files = [
  'UI/FocusMode/Content/ContentFocusModeState.swift',
  'UI/FocusMode/Content/ContentFocusModeView.swift',
  'UI/FocusMode/Content/ContentBrainstormView.swift',
  'UI/FocusMode/Content/ContentDraftView.swift',
  'UI/FocusMode/Content/ContentPolishView.swift'
]

content_files.each do |file|
  add_file_with_absolute_path(content_group, file, target)
end

project.save
puts "Project saved successfully! Added focus mode redesign files."
