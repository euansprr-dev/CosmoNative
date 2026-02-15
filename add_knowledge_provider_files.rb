#!/usr/bin/env ruby
# Add KnowledgeDataProvider.swift and ReadwiseService.swift to pbxproj

pbxproj_path = File.join(__dir__, 'CosmoOS.xcodeproj', 'project.pbxproj')
content = File.read(pbxproj_path)

# IDs - must be globally unique
KDP_FILE_REF   = '7A2E9F31B4C8D5E610F27A3B'
KDP_BUILD_FILE = '3B1C7D42A5E8F6970D2A3B4C'
RWS_FILE_REF   = '8B3FA042C5D9E6F721A38B4C'
RWS_BUILD_FILE = '4C2D8E53B6F9A7081E3B4C5D'

# 1. Add PBXBuildFile entries (after KnowledgeDimensionData build file)
anchor = '9F77F9CDE65AB234B02F5A10 /* KnowledgeDimensionData.swift in Sources */'
unless content.include?(KDP_BUILD_FILE)
  build_entries = <<~ENTRIES
  \t\t#{KDP_BUILD_FILE} /* KnowledgeDataProvider.swift in Sources */ = {isa = PBXBuildFile; fileRef = #{KDP_FILE_REF} /* KnowledgeDataProvider.swift */; };
  \t\t#{RWS_BUILD_FILE} /* ReadwiseService.swift in Sources */ = {isa = PBXBuildFile; fileRef = #{RWS_FILE_REF} /* ReadwiseService.swift */; };
  ENTRIES
  content.sub!(
    /^(\t\t#{Regexp.escape(anchor)}.*)$/,
    "\\1\n#{build_entries.chomp}"
  )
end

# 2. Add PBXFileReference entries (after KnowledgeDimensionData file ref)
anchor_ref = 'E0B9F921368693A8CB8F5582 /* KnowledgeDimensionData.swift */'
unless content.include?(KDP_FILE_REF)
  file_entries = <<~ENTRIES
  \t\t#{KDP_FILE_REF} /* KnowledgeDataProvider.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KnowledgeDataProvider.swift; sourceTree = "<group>"; };
  \t\t#{RWS_FILE_REF} /* ReadwiseService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReadwiseService.swift; sourceTree = "<group>"; };
  ENTRIES
  content.sub!(
    /^(\t\t#{Regexp.escape(anchor_ref)} = \{[^}]+\};)$/,
    "\\1\n#{file_entries.chomp}"
  )
end

# 3. Add to Knowledge group (after KnowledgeDimensionData in group children)
knowledge_group_anchor = 'E0B9F921368693A8CB8F5582 /* KnowledgeDimensionData.swift */,'
unless content.include?("#{KDP_FILE_REF} /* KnowledgeDataProvider.swift */,")
  content.sub!(
    /^(\t\t\t\t#{Regexp.escape(knowledge_group_anchor)})$/,
    "\\1\n\t\t\t\t#{KDP_FILE_REF} /* KnowledgeDataProvider.swift */,"
  )
end

# 4. Add ReadwiseService to Services group (after SocialSyncService)
services_anchor = 'C7E42F1DA93B850612D4A7E3 /* SocialSyncService.swift */,'
unless content.include?("#{RWS_FILE_REF} /* ReadwiseService.swift */,")
  content.sub!(
    /^(\t\t\t\t#{Regexp.escape(services_anchor)})$/,
    "\\1\n\t\t\t\t#{RWS_FILE_REF} /* ReadwiseService.swift */,"
  )
end

# 5. Add to Sources build phase (after KnowledgeDimensionData in Sources)
sources_anchor = '9F77F9CDE65AB234B02F5A10 /* KnowledgeDimensionData.swift in Sources */,'
unless content.include?("#{KDP_BUILD_FILE} /* KnowledgeDataProvider.swift in Sources */,")
  content.sub!(
    /^(\t\t\t\t#{Regexp.escape(sources_anchor)})$/,
    "\\1\n\t\t\t\t#{KDP_BUILD_FILE} /* KnowledgeDataProvider.swift in Sources */,\n\t\t\t\t#{RWS_BUILD_FILE} /* ReadwiseService.swift in Sources */,"
  )
end

File.write(pbxproj_path, content)
puts "Successfully added KnowledgeDataProvider.swift and ReadwiseService.swift to pbxproj"
