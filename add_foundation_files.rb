#!/usr/bin/env ruby
# Add WP0 Foundation files to Xcode project

pbxproj_path = "/Users/euanspencer/CosmoOS-Swift/CosmoOS.xcodeproj/project.pbxproj"
content = File.read(pbxproj_path)

# Unique IDs for each entry
DIE_FILEREF  = "026510885198471380493312"
DIE_BUILD    = "062513504312268541728534"
PC_FILEREF   = "554321012380251170741668"
PC_BUILD     = "442590511821024001541705"
SSV_FILEREF  = "508034948877066137948206"
SSV_BUILD    = "624520441708046250237305"
COMP_GROUP   = "511305065736827059739422"

# 1. PBXBuildFile entries — insert after the DimensionXPRouter build file
build_anchor = "2CA61A66B8D98F5F6A1709EB /* DimensionXPRouter.swift in Sources */ = {isa = PBXBuildFile; fileRef = 94C6CDD22AA0C20F7F01F15B /* DimensionXPRouter.swift */; };"
build_insert = <<~ENTRIES
#{build_anchor}
		#{DIE_BUILD} /* DimensionIndexEngine.swift in Sources */ = {isa = PBXBuildFile; fileRef = #{DIE_FILEREF} /* DimensionIndexEngine.swift */; };
		#{PC_BUILD} /* PlaceholderCard.swift in Sources */ = {isa = PBXBuildFile; fileRef = #{PC_FILEREF} /* PlaceholderCard.swift */; };
		#{SSV_BUILD} /* SanctuarySettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = #{SSV_FILEREF} /* SanctuarySettingsView.swift */; };
ENTRIES
content.sub!(build_anchor, build_insert.chomp) || abort("Failed to insert build files")

# 2. PBXFileReference entries — insert after DimensionXPRouter file reference
fileref_anchor = "94C6CDD22AA0C20F7F01F15B /* DimensionXPRouter.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DimensionXPRouter.swift; sourceTree = \"<group>\"; };"
fileref_insert = <<~ENTRIES
#{fileref_anchor}
		#{DIE_FILEREF} /* DimensionIndexEngine.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DimensionIndexEngine.swift; sourceTree = "<group>"; };
		#{PC_FILEREF} /* PlaceholderCard.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PlaceholderCard.swift; sourceTree = "<group>"; };
		#{SSV_FILEREF} /* SanctuarySettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SanctuarySettingsView.swift; sourceTree = "<group>"; };
ENTRIES
content.sub!(fileref_anchor, fileref_insert.chomp) || abort("Failed to insert file references")

# 3. Add DimensionIndexEngine to LevelSystem group (after DimensionXPRouter)
levelsys_anchor = "94C6CDD22AA0C20F7F01F15B /* DimensionXPRouter.swift */,\n"
levelsys_insert = "#{levelsys_anchor}\t\t\t\t#{DIE_FILEREF} /* DimensionIndexEngine.swift */,\n"
content.sub!(levelsys_anchor, levelsys_insert) || abort("Failed to add to LevelSystem group")

# 4. Create Components group and add to Sanctuary group
# Add Components group reference to Sanctuary group (after Dimensions ref)
sanc_anchor = "C4D6D6CCE5EDBF33533BD69C /* Dimensions */,"
sanc_insert = "#{sanc_anchor}\n\t\t\t\t#{COMP_GROUP} /* Components */,"
content.sub!(sanc_anchor, sanc_insert) || abort("Failed to add Components to Sanctuary group")

# Add the Components group definition (before the Settings group)
settings_group_anchor = "825D94A8080BB5647AABB3FD /* Settings */ = {"
components_group = <<~GROUP
#{COMP_GROUP} /* Components */ = {
			isa = PBXGroup;
			children = (
				#{PC_FILEREF} /* PlaceholderCard.swift */,
			);
			path = Components;
			sourceTree = "<group>";
		};
		#{settings_group_anchor}
GROUP
content.sub!(settings_group_anchor, components_group.chomp) || abort("Failed to create Components group")

# 5. Add SanctuarySettingsView to Settings group
settings_child_anchor = "EE540F151E53E884BD71664F /* SettingsMenuButton.swift */,"
settings_child_insert = "#{settings_child_anchor}\n\t\t\t\t#{SSV_FILEREF} /* SanctuarySettingsView.swift */,"
content.sub!(settings_child_anchor, settings_child_insert) || abort("Failed to add to Settings group")

# 6. Add all three to Sources build phase (after DimensionXPRouter in Sources)
sources_anchor = "2CA61A66B8D98F5F6A1709EB /* DimensionXPRouter.swift in Sources */,"
sources_insert = <<~ENTRIES
#{sources_anchor}
				#{DIE_BUILD} /* DimensionIndexEngine.swift in Sources */,
				#{PC_BUILD} /* PlaceholderCard.swift in Sources */,
				#{SSV_BUILD} /* SanctuarySettingsView.swift in Sources */,
ENTRIES
content.sub!(sources_anchor, sources_insert.chomp) || abort("Failed to add to Sources build phase")

File.write(pbxproj_path, content)
puts "Successfully added 3 WP0 Foundation files to project.pbxproj"
