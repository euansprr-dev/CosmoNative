#!/usr/bin/env python3
import uuid
import re

# Read the project file
with open('CosmoOS.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# Generate UUIDs for the new file
file_ref_uuid = ''.join(str(uuid.uuid4()).replace('-', '').upper()[:24])
build_file_uuid = ''.join(str(uuid.uuid4()).replace('-', '').upper()[:24])

# Find the PBXBuildFile section
build_file_section = re.search(r'/\* Begin PBXBuildFile section \*/', content)
if build_file_section:
    insert_pos = build_file_section.end()
    new_build_file = f"\n\t\t{build_file_uuid} /* CalendarItemEditorCard.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_uuid} /* CalendarItemEditorCard.swift */; }};"
    content = content[:insert_pos] + new_build_file + content[insert_pos:]

# Find the PBXFileReference section
file_ref_section = re.search(r'/\* Begin PBXFileReference section \*/', content)
if file_ref_section:
    insert_pos = file_ref_section.end()
    new_file_ref = f"\n\t\t{file_ref_uuid} /* CalendarItemEditorCard.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CalendarItemEditorCard.swift; sourceTree = \"<group>\"; }};"
    content = content[:insert_pos] + new_file_ref + content[insert_pos:]

# Find the Calendar group and add the file reference
# First, find where CalendarMainView.swift is referenced in the group
calendar_main_match = re.search(r'(\t+)72C9DF763E458281731637BC /\* CalendarMainView\.swift \*/,', content)
if calendar_main_match:
    indent = calendar_main_match.group(1)
    insert_pos = calendar_main_match.end()
    new_group_entry = f"\n{indent}{file_ref_uuid} /* CalendarItemEditorCard.swift */,"
    content = content[:insert_pos] + new_group_entry + content[insert_pos:]

# Find the Sources build phase and add the build file
# Look for CalendarMainView.swift in Sources
sources_match = re.search(r'(\t+)288CFAF4ADF2393A26A05980 /\* CalendarMainView\.swift in Sources \*/,', content)
if sources_match:
    indent = sources_match.group(1)
    insert_pos = sources_match.end()
    new_sources_entry = f"\n{indent}{build_file_uuid} /* CalendarItemEditorCard.swift in Sources */,"
    content = content[:insert_pos] + new_sources_entry + content[insert_pos:]

# Write the modified project file
with open('CosmoOS.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print(f"Added CalendarItemEditorCard.swift to project")
print(f"File Reference UUID: {file_ref_uuid}")
print(f"Build File UUID: {build_file_uuid}")
