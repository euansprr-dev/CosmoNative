#!/usr/bin/env ruby
# Add source files to the CosmoOS target, creating intermediate groups as
# needed. Paths are repo-relative. Idempotent: files already in the project
# are skipped.
#
#   ruby scripts/add_files_to_target.rb Services/AttachmentCloudStore.swift UI/Foo/Bar.swift

require 'xcodeproj'

repo_root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(repo_root, 'CosmoOS.xcodeproj'))
target = project.targets.find { |t| t.name == 'CosmoOS' } or abort 'CosmoOS target not found'

added = 0
ARGV.each do |rel_path|
  abs = File.join(repo_root, rel_path)
  abort "missing file: #{rel_path}" unless File.exist?(abs)

  dir = File.dirname(rel_path)
  group = dir == '.' ? project.main_group : project.main_group.find_subpath(dir, true)
  group.set_source_tree('<group>') if group.source_tree.nil?

  basename = File.basename(rel_path)
  if group.files.any? { |f| f.path == basename || f.path == rel_path }
    puts "skip (already present): #{rel_path}"
    next
  end

  file_ref = group.new_reference(abs)
  target.add_file_references([file_ref]) if rel_path.end_with?('.swift')
  puts "added: #{rel_path}"
  added += 1
end

project.save if added > 0
puts added > 0 ? "✅ saved (#{added} file(s))" : '✅ nothing to do'
