# frozen_string_literal: true

require "digest"
require "pathname"

dir = File.expand_path(ARGV.fetch(0))
abort "evidence directory not found: #{dir}" unless Dir.exist?(dir)

text_extensions = %w[.json .html .log .txt .md]
secret_patterns = [
  /Authorization:\s*Bearer\s+[A-Za-z0-9._-]{16,}/i,
  /refresh_token\s*[:=]\s*["']?[A-Za-z0-9._-]{12,}/i,
  /E2E_PASSWORD\s*=\s*[^\s]+/i,
  /password\s*=\s*[^\s]+/i
]

Dir.glob(File.join(dir, "*")).sort.each do |path|
  next unless File.file?(path)
  next unless text_extensions.include?(File.extname(path).downcase)

  content = File.read(path, mode: "rb").force_encoding("UTF-8")
  next unless content.valid_encoding?

  secret_patterns.each do |pattern|
    abort "potential secret marker detected in #{File.basename(path)}" if content.match?(pattern)
  end
end

files = Dir.glob(File.join(dir, "*"))
           .select { |path| File.file?(path) && File.basename(path) != "SHA256SUMS" }
           .sort

File.open(File.join(dir, "SHA256SUMS"), "w") do |out|
  files.each do |path|
    out.puts "#{Digest::SHA256.file(path).hexdigest}  #{File.basename(path)}"
  end
end

puts "EVIDENCE_FINALIZE=PASS"
puts "FILES=#{files.length}"
puts "SHA256SUMS=#{File.join(dir, "SHA256SUMS")}"
