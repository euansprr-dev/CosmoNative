#!/usr/bin/env ruby
# Add Cosmo Agent files to the Xcode project

require 'securerandom'

PBXPROJ = "CosmoOS.xcodeproj/project.pbxproj"

# Generate unique 24-char hex IDs
def gen_id
  SecureRandom.hex(12).upcase
end

# Files to add: [relative_path, filename]
files = [
  # Agent/Models
  ["Agent/Models", "AgentTypes.swift"],
  ["Agent/Models", "AgentPreference.swift"],
  # Agent/Core
  ["Agent/Core", "LLMProviderAdapter.swift"],
  ["Agent/Core", "AgentToolRegistry.swift"],
  ["Agent/Core", "AgentToolExecutor.swift"],
  ["Agent/Core", "AgentContextAssembler.swift"],
  ["Agent/Core", "CosmoAgentService.swift"],
  # Agent/Bridges
  ["Agent/Bridges", "MessagingBridgeProtocol.swift"],
  ["Agent/Bridges", "WhisperTranscriptionService.swift"],
  ["Agent/Bridges", "TelegramBridgeService.swift"],
  # Agent/Proactive
  ["Agent/Proactive", "AgentBriefGenerator.swift"],
  ["Agent/Proactive", "AgentProactiveScheduler.swift"],
  # Agent/Memory
  ["Agent/Memory", "ConversationMemoryService.swift"],
  # Agent/Preferences
  ["Agent/Preferences", "PreferenceLearningEngine.swift"],
  # Agent/Pipeline
  ["Agent/Pipeline", "BrainstormToThinkspacePipeline.swift"],
  # Settings
  ["Settings", "CosmoAgentSettingsTab.swift"],
]

# Generate IDs for each file (fileRef and buildFile)
file_entries = files.map do |path, name|
  {
    path: path,
    name: name,
    file_ref_id: gen_id,
    build_file_id: gen_id,
  }
end

# Generate group IDs
agent_group_id = gen_id
models_group_id = gen_id
core_group_id = gen_id
bridges_group_id = gen_id
proactive_group_id = gen_id
memory_group_id = gen_id
preferences_group_id = gen_id
pipeline_group_id = gen_id

content = File.read(PBXPROJ)

# 1. Add PBXBuildFile entries (after first line of build file section)
build_file_lines = file_entries.map do |e|
  "\t\t#{e[:build_file_id]} /* #{e[:name]} in Sources */ = {isa = PBXBuildFile; fileRef = #{e[:file_ref_id]} /* #{e[:name]} */; };"
end.join("\n")

content.sub!("/* Begin PBXBuildFile section */\n", "/* Begin PBXBuildFile section */\n#{build_file_lines}\n")

# 2. Add PBXFileReference entries
file_ref_lines = file_entries.map do |e|
  "\t\t#{e[:file_ref_id]} /* #{e[:name]} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{e[:name]}; sourceTree = \"<group>\"; };"
end.join("\n")

content.sub!("/* Begin PBXFileReference section */\n", "/* Begin PBXFileReference section */\n#{file_ref_lines}\n")

# 3. Add PBXGroup entries for Agent subgroups
def group_children(entries, path)
  entries.select { |e| e[:path] == path }.map { |e| "\t\t\t\t#{e[:file_ref_id]} /* #{e[:name]} */," }.join("\n")
end

# Settings file ref ID for CosmoAgentSettingsTab
settings_entry = file_entries.find { |e| e[:name] == "CosmoAgentSettingsTab.swift" }

# Agent subgroups
agent_groups = <<~GROUPS
\t\t#{models_group_id} /* Models */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
#{group_children(file_entries, "Agent/Models")}
\t\t\t);
\t\t\tpath = Models;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t#{core_group_id} /* Core */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
#{group_children(file_entries, "Agent/Core")}
\t\t\t);
\t\t\tpath = Core;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t#{bridges_group_id} /* Bridges */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
#{group_children(file_entries, "Agent/Bridges")}
\t\t\t);
\t\t\tpath = Bridges;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t#{proactive_group_id} /* Proactive */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
#{group_children(file_entries, "Agent/Proactive")}
\t\t\t);
\t\t\tpath = Proactive;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t#{memory_group_id} /* Memory */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
#{group_children(file_entries, "Agent/Memory")}
\t\t\t);
\t\t\tpath = Memory;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t#{preferences_group_id} /* Preferences */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
#{group_children(file_entries, "Agent/Preferences")}
\t\t\t);
\t\t\tpath = Preferences;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t#{pipeline_group_id} /* Pipeline */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
#{group_children(file_entries, "Agent/Pipeline")}
\t\t\t);
\t\t\tpath = Pipeline;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t#{agent_group_id} /* Agent */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t#{models_group_id} /* Models */,
\t\t\t\t#{core_group_id} /* Core */,
\t\t\t\t#{bridges_group_id} /* Bridges */,
\t\t\t\t#{proactive_group_id} /* Proactive */,
\t\t\t\t#{memory_group_id} /* Memory */,
\t\t\t\t#{preferences_group_id} /* Preferences */,
\t\t\t\t#{pipeline_group_id} /* Pipeline */,
\t\t\t);
\t\t\tpath = Agent;
\t\t\tsourceTree = "<group>";
\t\t};
GROUPS

content.sub!("/* Begin PBXGroup section */\n", "/* Begin PBXGroup section */\n#{agent_groups}")

# 4. Add Agent group to main group children (after AI)
content.sub!(
  /(\t\t\t\tA765128C0A995AB77914B236 \/\* AI \*\/,)/,
  "\\1\n\t\t\t\t#{agent_group_id} /* Agent */,"
)

# 5. Add CosmoAgentSettingsTab to Settings group
# Find the Settings group and add the file ref
settings_group_pattern = /(825D94A8080BB5647AABB3FD \/\* Settings \*\/ = \{\s*isa = PBXGroup;\s*children = \()/
content.sub!(settings_group_pattern, "\\1\n\t\t\t\t#{settings_entry[:file_ref_id]} /* CosmoAgentSettingsTab.swift */,")

# 6. Add to PBXSourcesBuildPhase
build_phase_lines = file_entries.map do |e|
  "\t\t\t\t#{e[:build_file_id]} /* #{e[:name]} in Sources */,"
end.join("\n")

content.sub!(
  /(1300E07822E59FAD820458E4 \/\* Sources \*\/ = \{\s*isa = PBXSourcesBuildPhase;\s*buildActionMask = 2147483647;\s*files = \()/,
  "\\1\n#{build_phase_lines}"
)

File.write(PBXPROJ, content)
puts "✅ Added #{file_entries.length} files to project.pbxproj"
puts "   Agent group: #{agent_group_id}"
file_entries.each { |e| puts "   #{e[:name]}: ref=#{e[:file_ref_id]} build=#{e[:build_file_id]}" }
