#!/usr/bin/env ruby
# Add missing PBXFileReference entries for KnowledgeDataProvider and ReadwiseService

pbxproj_path = File.join(__dir__, 'CosmoOS.xcodeproj', 'project.pbxproj')
content = File.read(pbxproj_path)

KDP_FILE_REF = '7A2E9F31B4C8D5E610F27A3B'
RWS_FILE_REF = '8B3FA042C5D9E6F721A38B4C'

kdp_line = "\t\t#{KDP_FILE_REF} /* KnowledgeDataProvider.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KnowledgeDataProvider.swift; sourceTree = \"<group>\"; };"
rws_line = "\t\t#{RWS_FILE_REF} /* ReadwiseService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReadwiseService.swift; sourceTree = \"<group>\"; };"

# Check for the actual PBXFileReference line, not just the ID
unless content.include?("#{KDP_FILE_REF} /* KnowledgeDataProvider.swift */ = {isa = PBXFileReference")
  # Insert after the KnowledgeDimensionData file reference line
  anchor_line = content.lines.find { |l| l.include?('E0B9F921368693A8CB8F5582') && l.include?('PBXFileReference') }
  if anchor_line
    content.sub!(anchor_line, anchor_line.chomp + "\n" + kdp_line + "\n" + rws_line + "\n")
    File.write(pbxproj_path, content)
    puts "Added PBXFileReference entries successfully"
  else
    puts "ERROR: Could not find anchor line for KnowledgeDimensionData PBXFileReference"
  end
else
  puts "PBXFileReference entries already exist"
end
