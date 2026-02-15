#!/usr/bin/env ruby
# Add floating blocks files to Xcode project

require 'securerandom'

pbxproj_path = "CosmoOS.xcodeproj/project.pbxproj"
content = File.read(pbxproj_path)

# Files to add
files = [
  {
    name: "FocusFloatingBlocksManager.swift",
    path: "UI/FocusMode/FocusFloatingBlocksManager.swift",
    file_ref: SecureRandom.hex(12).upcase,
    build_ref: SecureRandom.hex(12).upcase,
  },
  {
    name: "FocusFloatingBlockView.swift",
    path: "UI/FocusMode/FocusFloatingBlockView.swift",
    file_ref: SecureRandom.hex(12).upcase,
    build_ref: SecureRandom.hex(12).upcase,
  },
  {
    name: "FocusBlockContextMenu.swift",
    path: "UI/FocusMode/FocusBlockContextMenu.swift",
    file_ref: SecureRandom.hex(12).upcase,
    build_ref: SecureRandom.hex(12).upcase,
  },
]

files.each do |file|
  # Add PBXBuildFile entry (after last FocusConnect entry)
  build_file_entry = "\t\t#{file[:build_ref]} /* #{file[:name]} in Sources */ = {isa = PBXBuildFile; fileRef = #{file[:file_ref]} /* #{file[:name]} */; };"
  content.sub!(
    /(\t\tC8769DAEE2A210F561AAB639 \/\* FocusConnectManager\.swift in Sources \*\/ = \{.*?\};)/,
    "\\1\n#{build_file_entry}"
  )

  # Add PBXFileReference entry (after FocusConnectManager)
  file_ref_entry = "\t\t#{file[:file_ref]} /* #{file[:name]} */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; name = #{file[:name]}; path = #{file[:path]}; sourceTree = SOURCE_ROOT; };"
  content.sub!(
    /(\t\tFF3A7E4BE7F40FDF8D76C271 \/\* FocusConnectManager\.swift \*\/ = \{.*?\};)/,
    "\\1\n#{file_ref_entry}"
  )

  # Add to FocusMode group (after FocusConnectManager in the children list)
  content.sub!(
    /(\t\t\t\tFF3A7E4BE7F40FDF8D76C271 \/\* FocusConnectManager\.swift \*\/,)/,
    "\\1\n\t\t\t\t#{file[:file_ref]} /* #{file[:name]} */,"
  )

  # Add to Sources build phase (after FocusConnectManager in Sources)
  content.sub!(
    /(\t\t\t\tC8769DAEE2A210F561AAB639 \/\* FocusConnectManager\.swift in Sources \*\/,)/,
    "\\1\n\t\t\t\t#{file[:build_ref]} /* #{file[:name]} in Sources */,"
  )
end

File.write(pbxproj_path, content)
puts "Added #{files.length} files to Xcode project"
files.each { |f| puts "  - #{f[:name]} (#{f[:path]})" }
