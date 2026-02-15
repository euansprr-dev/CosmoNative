#!/usr/bin/env ruby
# Add missing PBXFileReference entries for KnowledgeDataProvider and ReadwiseService

pbxproj_path = File.join(__dir__, 'CosmoOS.xcodeproj', 'project.pbxproj')
content = File.read(pbxproj_path)

KDP_FILE_REF = '7A2E9F31B4C8D5E610F27A3B'
RWS_FILE_REF = '8B3FA042C5D9E6F721A38B4C'

# Add PBXFileReference entries after the KnowledgeDimensionData file reference
anchor = 'E0B9F921368693A8CB8F5582 /* KnowledgeDimensionData.swift */ = {isa = PBXFileReference;'

unless content.include?("#{KDP_FILE_REF} /* KnowledgeDataProvider.swift */")
  # Find the full line containing the anchor
  content.sub!(
    /(#{Regexp.escape(anchor)}[^\n]+\n)/
  ) do |match|
    match +
    "\t\t#{KDP_FILE_REF} /* KnowledgeDataProvider.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KnowledgeDataProvider.swift; sourceTree = \"<group>\"; };\n" +
    "\t\t#{RWS_FILE_REF} /* ReadwiseService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReadwiseService.swift; sourceTree = \"<group>\"; };\n"
  end
end

File.write(pbxproj_path, content)
puts "Added PBXFileReference entries"
