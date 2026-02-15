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

# --- Canvas group ---
canvas_group = project.main_group.find_subpath('Canvas') || project.main_group.new_group('Canvas')

canvas_files = [
  'Canvas/KnowledgePulseLineView.swift',
  'Canvas/CanvasConnectionLinesLayer.swift',
  'Canvas/DragToConnectManager.swift',
  'Canvas/DragToConnectOverlay.swift',
  'Canvas/BlockContextMenu.swift',
  'Canvas/CanvasBlockFrameTracker.swift'
]

canvas_files.each do |f|
  add_file_with_absolute_path(canvas_group, f, target)
end

# --- UI/FocusMode/CosmoAI group ---
focus_mode_group = project.main_group.find_subpath('UI/FocusMode') || project.main_group.new_group('UI').new_group('FocusMode')
cosmo_ai_group = focus_mode_group.find_subpath('CosmoAI') || focus_mode_group.new_group('CosmoAI')

cosmo_ai_files = [
  'UI/FocusMode/CosmoAI/CosmoAIFocusModeView.swift',
  'UI/FocusMode/CosmoAI/CosmoAIFocusModeViewModel.swift',
  'UI/FocusMode/CosmoAI/CosmoAIConversationPanel.swift'
]

cosmo_ai_files.each do |f|
  add_file_with_absolute_path(cosmo_ai_group, f, target)
end

# --- UI/FocusMode group (root-level focus mode files) ---
focus_connect_files = [
  'UI/FocusMode/FocusConnectManager.swift',
  'UI/FocusMode/FocusConnectionLinesLayer.swift'
]

focus_connect_files.each do |f|
  add_file_with_absolute_path(focus_mode_group, f, target)
end

project.save
puts "\nDone! All Thinkspace Revolution files added to Xcode project."
