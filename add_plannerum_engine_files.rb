require "securerandom"

def gen_id
  SecureRandom.hex(12).upcase
end

pbxproj = File.read("CosmoOS.xcodeproj/project.pbxproj")

files = [
  { name: "DeepWorkSessionEngine.swift", path: "AI/DeepWorkSessionEngine.swift", group: "AI" },
  { name: "SessionTimerBar.swift", path: "UI/Plannerum/Components/SessionTimerBar.swift", group: "Components" },
  { name: "SessionSummaryCard.swift", path: "UI/Plannerum/Components/SessionSummaryCard.swift", group: "Components" },
  { name: "CalendarSyncService.swift", path: "Scheduler/CalendarSyncService.swift", group: "Scheduler" },
]

build_file_entries = []
file_ref_entries = []
source_entries = []
group_entries = {}

files.each do |f|
  ref_id = gen_id
  build_id = gen_id

  while pbxproj.include?(ref_id) || pbxproj.include?(build_id)
    ref_id = gen_id
    build_id = gen_id
  end

  build_file_entries << "\t\t#{build_id} /* #{f[:name]} in Sources */ = {isa = PBXBuildFile; fileRef = #{ref_id} /* #{f[:name]} */; };"
  file_ref_entries << "\t\t#{ref_id} /* #{f[:name]} */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; name = #{f[:name]}; path = #{f[:path]}; sourceTree = SOURCE_ROOT; };"
  source_entries << "\t\t\t\t#{build_id} /* #{f[:name]} in Sources */,"

  group_entries[f[:group]] ||= []
  group_entries[f[:group]] << "\t\t\t\t#{ref_id} /* #{f[:name]} */,"

  puts "#{f[:name]}: ref=#{ref_id} build=#{build_id}"
end

# 1. Add PBXBuildFile entries
marker = "/* End PBXBuildFile section */"
pbxproj.sub!(marker, build_file_entries.join("\n") + "\n" + marker)

# 2. Add PBXFileReference entries
marker = "/* End PBXFileReference section */"
pbxproj.sub!(marker, file_ref_entries.join("\n") + "\n" + marker)

# 3. Add to Sources build phase - find the closing of the files list
# Look for the pattern right before End PBXSourcesBuildPhase
lines = pbxproj.split("\n")
insert_idx = nil
lines.each_with_index do |line, idx|
  if line.include?("/* End PBXSourcesBuildPhase section */")
    # Go back to find the closing ); of files array
    (idx - 1).downto(0) do |j|
      if lines[j].strip == ");"
        insert_idx = j
        break
      end
    end
    break
  end
end

if insert_idx
  source_entries.each_with_index do |entry, i|
    lines.insert(insert_idx + i, entry)
  end
  pbxproj = lines.join("\n")
  puts "Added #{source_entries.length} source entries at line #{insert_idx}"
end

# 4. Add to groups
group_entries.each do |group_name, refs|
  case group_name
  when "AI"
    target = "F7E8D9C0A1B2C3D4E5F60001 /* TaskRecurrenceEngine.swift */,"
    if pbxproj.include?(target)
      pbxproj.sub!(target, target + "\n" + refs.join("\n"))
      puts "Added #{refs.length} files to AI group"
    end
  when "Components"
    target = "4E3A975EDBF2EFAD8CB9BC29 /* TaskIntentPicker.swift */,"
    if pbxproj.include?(target)
      pbxproj.sub!(target, target + "\n" + refs.join("\n"))
      puts "Added #{refs.length} files to Components group"
    end
  when "Scheduler"
    # Find any file in Scheduler group
    if pbxproj =~ /(\w{24} \/\* RecurrenceRule\.swift \*\/,)/
      pbxproj.sub!($1, $1 + "\n" + refs.join("\n"))
      puts "Added #{refs.length} files to Scheduler group"
    else
      puts "WARNING: Could not find Scheduler group"
    end
  end
end

File.write("CosmoOS.xcodeproj/project.pbxproj", pbxproj)
puts "Done! Added #{files.length} files to Xcode project."
