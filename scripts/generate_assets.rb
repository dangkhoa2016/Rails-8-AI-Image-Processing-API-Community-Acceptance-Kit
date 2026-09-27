# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "open3"

ROOT = File.expand_path("..", __dir__)
OUT = File.join(ROOT, "assets", "input")
FileUtils.mkdir_p(OUT)

def run!(*cmd)
  stdout, stderr, status = Open3.capture3(*cmd)
  raise "command failed: #{cmd.join(" ")}\n#{stdout}\n#{stderr}" unless status.success?
  stdout
end

def write_svg(path, width, height, body)
  File.write(path, <<~SVG)
    <svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">
      #{body}
    </svg>
  SVG
end

def render_svg(svg_path, output_path)
  run!("vips", "copy", svg_path, output_path)
end

tmp = File.join(ROOT, "assets", ".generated")
FileUtils.rm_rf(tmp)
FileUtils.mkdir_p(tmp)

rgb_svg = File.join(tmp, "rgb-gradient.svg")
write_svg(rgb_svg, 640, 480, <<~SVG)
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#001020"/>
      <stop offset="50%" stop-color="#7f7f7f"/>
      <stop offset="100%" stop-color="#fff0d0"/>
    </linearGradient>
  </defs>
  <rect width="640" height="480" fill="url(#g)"/>
  <rect x="40" y="40" width="180" height="140" fill="none" stroke="#ffffff" stroke-width="8"/>
  <ellipse cx="455" cy="185" rx="105" ry="105" fill="none" stroke="#ffe600" stroke-width="10"/>
  <line x1="20" y1="440" x2="620" y2="300" stroke="#000000" stroke-width="12"/>
SVG
rgb_rgba = File.join(tmp, "rgb-gradient-rgba.png")
render_svg(rgb_svg, rgb_rgba)
run!("vips", "extract_band", rgb_rgba,
     File.join(OUT, "rgb-gradient-640x480.png"), "0", "--n", "3")
run!("vips", "thumbnail", File.join(OUT, "rgb-gradient-640x480.png"),
     File.join(OUT, "rgb-gradient-512x384.webp"), "512", "--height", "384", "--size", "force", "--export-profile", "srgb")

alpha_svg = File.join(tmp, "alpha-shapes.svg")
write_svg(alpha_svg, 512, 512, <<~SVG)
  <rect width="512" height="512" fill="none"/>
  <rect x="40" y="40" width="432" height="432" rx="64" fill="#145ab4" fill-opacity="0.43"/>
  <ellipse cx="256" cy="256" rx="156" ry="156" fill="#eb4b4b" fill-opacity="0.70"/>
  <rect x="180" y="40" width="152" height="432" fill="#1edc78" fill-opacity="0.82"/>
SVG
render_svg(alpha_svg, File.join(OUT, "alpha-shapes-512x512.png"))

person_svg = File.join(tmp, "person-scene.svg")
write_svg(person_svg, 768, 768, <<~SVG)
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#dcebf5"/>
      <stop offset="100%" stop-color="#a0bec8"/>
    </linearGradient>
  </defs>
  <rect width="768" height="768" fill="url(#bg)"/>
  <rect y="590" width="768" height="178" fill="#5f7d55"/>
  <rect x="70" y="130" width="165" height="230" fill="#b4cddc"/>
  <rect x="540" y="95" width="160" height="260" fill="#cdb996"/>
  <rect x="310" y="515" width="65" height="220" rx="24" fill="#282d37"/>
  <rect x="393" y="515" width="65" height="220" rx="24" fill="#282d37"/>
  <rect x="270" y="300" width="228" height="265" rx="70" fill="#2d559b"/>
  <rect x="218" y="325" width="82" height="210" rx="35" fill="#cd9678"/>
  <rect x="468" y="325" width="82" height="210" rx="35" fill="#cd9678"/>
  <rect x="352" y="255" width="64" height="75" fill="#cd9678"/>
  <ellipse cx="385" cy="205" rx="80" ry="90" fill="#cd9678"/>
  <path d="M292 190 A92 90 0 0 1 475 190 L465 135 A100 90 0 0 0 305 135 Z" fill="#2d231e"/>
  <circle cx="350" cy="195" r="5" fill="#282828"/>
  <circle cx="420" cy="195" r="5" fill="#282828"/>
  <path d="M365 225 Q385 245 405 225" fill="none" stroke="#784641" stroke-width="3"/>
  <rect x="290" y="705" width="90" height="45" rx="18" fill="#191919"/>
  <rect x="388" y="705" width="90" height="45" rx="18" fill="#191919"/>
SVG
render_svg(person_svg, File.join(OUT, "person-scene-768x768.png"))

# Keep the committed EXIF-orientation fixture as a static authority fixture.
# It is intentionally not regenerated here because libvips CLI alone cannot
# portably author EXIF Orientation=6 without an additional metadata tool.
exif_path = File.join(OUT, "exif-orientation-480x640.jpg")
raise "missing static EXIF authority fixture: #{exif_path}" unless File.file?(exif_path)

File.binwrite(File.join(OUT, "corrupt-not-an-image.jpg"),
              "\xFF\xD8COMMUNITY-E2E-NOT-A-VALID-JPEG\x00\x01\x02".b)

assets = Dir.glob(File.join(OUT, "*")).select { |p| File.file?(p) }.sort.map do |path|
  {
    "file" => path.delete_prefix(ROOT + "/"),
    "bytes" => File.size(path),
    "sha256" => Digest::SHA256.file(path).hexdigest
  }
end

manifest = {
  "schema" => 1,
  "generator" => "scripts/generate_assets.rb",
  "notes" => {
    "exif-orientation-480x640.jpg" => "static authority fixture; EXIF Orientation=6"
  },
  "assets" => assets
}

File.write(File.join(ROOT, "assets", "manifest.json"), JSON.pretty_generate(manifest) + "\n")
File.open(File.join(ROOT, "assets", "SHA256SUMS"), "w") do |f|
  assets.each { |a| f.puts "#{a["sha256"]}  #{a["file"]}" }
end

FileUtils.rm_rf(tmp)
puts JSON.pretty_generate(manifest)
