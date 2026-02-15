#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'CosmoOS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.find { |t| t.name == 'CosmoOS' }

# Remove incorrectly added files first
files_to_remove = [
  'ActiveSessionTimerManager.swift',
  'TaskRecommendationEngine.swift',
  'PlannerumViewModel.swift',
  'TaskViewModel.swift',
  'FocusNowCard.swift',
  'DailyQuestsPanel.swift',
  'TodaysTasksPanel.swift',
  'UpcomingSection.swift',
  'CompletionAnimation.swift'
]

# Find and remove bad file references
project.files.each do |file_ref|
  next unless file_ref.path

  file_name = File.basename(file_ref.path)
  if files_to_remove.include?(file_name) && file_ref.path.include?('/')
    # This is likely a duplicate path - remove it
    puts "Removing bad reference: #{file_ref.path}"

    # Remove from build phase
    target.source_build_phase.files.each do |build_file|
      if build_file.file_ref == file_ref
        build_file.remove_from_project
        break
      end
    end

    # Remove file reference
    file_ref.remove_from_project
  end
end

project.save
puts "Cleaned up bad references"

# Reopen project
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'CosmoOS' }

def add_file_with_absolute_path(group, file_path, target)
  file_name = File.basename(file_path)

  # Check if file already exists in group
  existing = group.files.find { |f| File.basename(f.path.to_s) == file_name }
  if existing
    puts "File already exists: #{file_name}"
    return
  end

  # Get absolute path
  absolute_path = File.expand_path(file_path)

  # Create file reference with SOURCE_ROOT relative path
  file_ref = group.new_reference(file_path)
  file_ref.source_tree = 'SOURCE_ROOT'
  file_ref.path = file_path

  # Add to target's sources build phase
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{file_path}"
end

# --- Data/Models/LevelSystem group ---
data_group = project.main_group.children.find { |g| g.display_name == 'Data' }
models_group = data_group&.children&.find { |g| g.display_name == 'Models' }
levelsystem_group = models_group&.children&.find { |g| g.display_name == 'LevelSystem' }

if levelsystem_group
  add_file_with_absolute_path(levelsystem_group, 'Data/Models/LevelSystem/ActiveSessionTimerManager.swift', target)
else
  puts "Warning: Could not find Data/Models/LevelSystem group"
end

# --- AI group ---
ai_group = project.main_group.children.find { |g| g.display_name == 'AI' }
if ai_group
  add_file_with_absolute_path(ai_group, 'AI/TaskRecommendationEngine.swift', target)
else
  puts "Warning: Could not find AI group"
end

# --- UI/Plannerum group ---
ui_group = project.main_group.children.find { |g| g.display_name == 'UI' }
plannerum_group = ui_group&.children&.find { |g| g.display_name == 'Plannerum' }

unless plannerum_group
  puts "Error: Could not find UI/Plannerum group"
  exit 1
end

# Add PlannerumViewModel to Plannerum root
add_file_with_absolute_path(plannerum_group, 'UI/Plannerum/PlannerumViewModel.swift', target)

# Find or create Models subgroup
models_subgroup = plannerum_group.children.find { |g| g.display_name == 'Models' }
unless models_subgroup
  models_subgroup = plannerum_group.new_group('Models')
  models_subgroup.source_tree = 'SOURCE_ROOT'
  models_subgroup.path = 'UI/Plannerum/Models'
  puts "Created Models group"
end
add_file_with_absolute_path(models_subgroup, 'UI/Plannerum/Models/TaskViewModel.swift', target)

# Find or create Components subgroup
components_group = plannerum_group.children.find { |g| g.display_name == 'Components' }
unless components_group
  components_group = plannerum_group.new_group('Components')
  components_group.source_tree = 'SOURCE_ROOT'
  components_group.path = 'UI/Plannerum/Components'
  puts "Created Components group"
end

# Add component files
component_files = [
  'UI/Plannerum/Components/FocusNowCard.swift',
  'UI/Plannerum/Components/DailyQuestsPanel.swift',
  'UI/Plannerum/Components/TodaysTasksPanel.swift',
  'UI/Plannerum/Components/UpcomingSection.swift',
  'UI/Plannerum/Components/CompletionAnimation.swift'
]

component_files.each do |file|
  add_file_with_absolute_path(components_group, file, target)
end

project.save
puts "Project saved successfully!"
