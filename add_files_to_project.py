#!/usr/bin/env python3
"""
Script to add missing Swift files to the Xcode project.
"""
import uuid
import re

# Files to add
files_to_add = [
    ("Data/ConnectionStore.swift", "ConnectionStore.swift"),
    ("Canvas/Components/ConnectionSectionNavigator.swift", "ConnectionSectionNavigator.swift"),
    ("Canvas/Components/EditableConnectionSection.swift", "EditableConnectionSection.swift"),
    ("Editor/Components/ResearchComponents.swift", "ResearchComponents.swift"),
]

def generate_uuid():
    """Generate a UUID in Xcode format (8-4-4-4-12 hex digits, uppercase)"""
    return uuid.uuid4().hex[:24].upper()

def add_files_to_pbxproj(project_path):
    with open(project_path, 'r') as f:
        content = f.read()
    
    # Generate UUIDs for each file
    file_refs = {}
    build_files = {}
    
    for path, filename in files_to_add:
        file_ref_uuid = generate_uuid()
        build_file_uuid = generate_uuid()
        file_refs[filename] = (file_ref_uuid, path)
        build_files[filename] = (build_file_uuid, file_ref_uuid, filename)
    
    # Find the PBXBuildFile section
    build_file_section_match = re.search(r'(/\* Begin PBXBuildFile section \*/\n)', content)
    if build_file_section_match:
        insert_pos = build_file_section_match.end()
        # Add build file entries
        build_file_entries = []
        for filename, (build_uuid, ref_uuid, _) in build_files.items():
            entry = f"\t\t{build_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_uuid} /* {filename} */; }};\n"
            build_file_entries.append(entry)
        
        content = content[:insert_pos] + ''.join(build_file_entries) + content[insert_pos:]
    
    # Find the PBXFileReference section
    file_ref_section_match = re.search(r'(/\* Begin PBXFileReference section \*/\n)', content)
    if file_ref_section_match:
        insert_pos = file_ref_section_match.end()
        # Add file reference entries
        file_ref_entries = []
        for filename, (ref_uuid, path) in file_refs.items():
            entry = f"\t\t{ref_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{path}\"; sourceTree = \"<group>\"; }};\n"
            file_ref_entries.append(entry)
        
        content = content[:insert_pos] + ''.join(file_ref_entries) + content[insert_pos:]
    
    # Find the PBXSourcesBuildPhase section and add to files
    sources_section_match = re.search(r'(/\* Sources \*/ = \{[^}]*files = \(\n)', content)
    if sources_section_match:
        insert_pos = sources_section_match.end()
        # Add to build phase
        build_phase_entries = []
        for filename, (build_uuid, _, _) in build_files.items():
            entry = f"\t\t\t\t{build_uuid} /* {filename} in Sources */,\n"
            build_phase_entries.append(entry)
        
        content = content[:insert_pos] + ''.join(build_phase_entries) + content[insert_pos:]
    
    # Write back
    with open(project_path, 'w') as f:
        f.write(content)
    
    print(f"✅ Added {len(files_to_add)} files to project")
    for _, filename in files_to_add:
        print(f"   - {filename}")

if __name__ == "__main__":
    project_path = "/Users/euanspencer/Cosmo-Local-BCKP/CosmoOS/CosmoOS.xcodeproj/project.pbxproj"
    add_files_to_pbxproj(project_path)
