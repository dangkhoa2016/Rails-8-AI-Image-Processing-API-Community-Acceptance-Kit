# frozen_string_literal: true

require "fileutils"
require "optparse"

options = {}
OptionParser.new do |o|
  o.on("--site DIR") { |v| options[:site] = File.expand_path(v) }
  o.on("--out DIR") { |v| options[:out] = File.expand_path(v) }
end.parse!

root = File.expand_path("..", __dir__)
site = options[:site] || File.join(root, "site")
out = options[:out] || File.join(root, "dist", "huggingface-space")
template = File.join(root, "deploy", "huggingface", "README.template.md")

abort "missing site directory: #{site}" unless Dir.exist?(site)
abort "missing Hugging Face README template: #{template}" unless File.file?(template)
abort "site/index.html missing" unless File.file?(File.join(site, "index.html"))

FileUtils.rm_rf(out)
FileUtils.mkdir_p(out)

Dir.glob(File.join(site, "*"), File::FNM_DOTMATCH).each do |path|
  name = File.basename(path)
  next if %w[. ..].include?(name)
  FileUtils.cp_r(path, File.join(out, name))
end

FileUtils.cp(template, File.join(out, "README.md"))

puts "HF_STATIC_SPACE_EXPORT=PASS"
puts "OUT=#{out}"
puts "APP_FILE=#{File.join(out, "index.html")}"
puts "FILES=#{Dir.glob(File.join(out, "*")).count { |p| File.file?(p) }}"
