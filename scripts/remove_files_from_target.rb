#!/usr/bin/env ruby
# Remove source files from the CosmoOS project (file reference + build phase
# entries). Paths are repo-relative. Does NOT delete the files on disk — do
# that separately with git rm. Idempotent: paths not in the project are
# skipped.
#
#   ruby scripts/remove_files_from_target.rb Canvas/Foo.swift AI/Bar.swift

require 'xcodeproj'

repo_root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(repo_root, 'CosmoOS.xcodeproj'))

removed = 0
ARGV.each do |rel_path|
  refs = project.files.select do |f|
    f.real_path.to_s == File.join(repo_root, rel_path)
  rescue StandardError
    false
  end

  if refs.empty?
    puts "skip (not in project): #{rel_path}"
    next
  end

  refs.each do |ref|
    ref.remove_from_project
    removed += 1
    puts "removed: #{rel_path}"
  end
end

project.save if removed > 0
puts removed > 0 ? "✅ saved (#{removed} reference(s) removed)" : '✅ nothing to do'
