# frozen_string_literal: true

require "base64"
require "cgi"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "time"

options = {}
OptionParser.new do |o|
  o.on("--reports DIR") { |v| options[:reports] = File.expand_path(v) }
  o.on("--evidence DIR") { |v| options[:evidence] = File.expand_path(v) }
  o.on("--out DIR") { |v| options[:out] = File.expand_path(v) }
  o.on("--title TITLE") { |v| options[:title] = v }
  o.on("--source-url URL") { |v| options[:source_url] = v }
  o.on("--application-url URL") { |v| options[:application_url] = v }
end.parse!

root = File.expand_path("..", __dir__)
reports = options[:reports] || options[:evidence] || File.join(root, "report-preview")
evidence = options[:evidence]
out = options[:out] || File.join(root, "site")
title = options[:title] || "Rails 8 AI Image Processing API — Community Acceptance"
source_url = options[:source_url] || "https://github.com/dangkhoa2016/Rails-8-AI-Image-Processing-API-Community-Acceptance-Kit"
application_url = options[:application_url] || "https://github.com/dangkhoa2016/Rails-8-AI-Image-Processing-API"

required = %w[report.html report-compact.html gallery.html]
missing = required.reject { |name| File.file?(File.join(reports, name)) }
abort "missing report files in #{reports}: #{missing.join(", ")}" unless missing.empty?

FileUtils.rm_rf(out)
FileUtils.mkdir_p(out)

required.each do |name|
  FileUtils.cp(File.join(reports, name), File.join(out, name))
end

def safe_json(path)
  return nil unless path && File.file?(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError
  nil
end

summary = evidence ? safe_json(File.join(evidence, "summary.json")) : nil
auth = evidence ? safe_json(File.join(evidence, "auth-summary.json")) : nil
rate = evidence ? safe_json(File.join(evidence, "rate-limits-summary.json")) : nil
all_results = Array(summary && summary["results"]) + Array(auth && auth["results"]) + Array(rate && rate["results"])
counts = all_results.each_with_object(Hash.new(0)) { |row, h| h[row["status"].to_s] += 1 }
counts = (summary && summary["counts"]) || { "PASS" => 0, "FAIL" => 0, "SKIP" => 0 } if counts.empty?

target = summary && summary["base_url"]
generated = (summary && summary["generated_at_utc"]) || Time.now.utc.iso8601
mode = evidence ? "live-evidence" : "preview"

contact = File.join(root, "assets", "input-contact-sheet.jpg")
contact_uri = if File.file?(contact)
  "data:image/jpeg;base64,#{Base64.strict_encode64(File.binread(contact))}"
end

status =
  if evidence
    counts["FAIL"].to_i.zero? ? "PASS" : "FAIL"
  else
    "PREVIEW"
  end
status_class =
  case status
  when "PASS" then "pass"
  when "FAIL" then "fail"
  else "skip"
  end

metadata = {
  "schema" => 1,
  "site_title" => title,
  "mode" => mode,
  "status" => status,
  "generated_at_utc" => generated,
  "target" => target,
  "source_repository" => source_url,
  "application_repository" => application_url,
  "counts" => {
    "PASS" => counts["PASS"].to_i,
    "FAIL" => counts["FAIL"].to_i,
    "SKIP" => counts["SKIP"].to_i
  },
  "reports" => {
    "full" => "report.html",
    "compact" => "report-compact.html",
    "gallery" => "gallery.html"
  },
  "evidence_scope" => {
    "fixture_kind" => "synthetic_contract_fixture",
    "semantic_quality_benchmark" => false,
    "interpretation" => "Endpoint/encoding/prompt-mechanics evidence only; no model-quality or accuracy claim."
  }
}
File.write(File.join(out, "metadata.json"), JSON.pretty_generate(metadata) + "\n")

css = <<~CSS
  :root{--bg:#08101f;--panel:#111b31;--panel2:#17243f;--text:#eef4ff;--muted:#9eafd0;--line:#2a3d63;--accent:#7dd3fc;--pass:#4ade80;--fail:#fb7185;--skip:#fbbf24}
  *{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:radial-gradient(circle at top right,#142749 0,#08101f 42%,#060b15 100%);color:var(--text);font:15px/1.55 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
  a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}.wrap{max-width:1180px;margin:auto;padding:38px 22px 70px}.eyebrow{color:var(--accent);font-size:12px;letter-spacing:.12em;text-transform:uppercase;font-weight:750}.hero{display:grid;grid-template-columns:1.45fr .75fr;gap:22px;align-items:center}.hero h1{font-size:clamp(34px,5vw,62px);line-height:1.02;margin:10px 0 16px}.lead{font-size:18px;color:var(--muted);max-width:780px}.panel{background:rgba(17,27,49,.93);border:1px solid var(--line);border-radius:18px;padding:20px}.status{font-size:46px;font-weight:800}.pass{color:var(--pass)}.fail{color:var(--fail)}.skip{color:var(--skip)}.metrics{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-top:18px}.metric{background:#0b1427;border:1px solid var(--line);border-radius:14px;padding:14px}.metric b{display:block;font-size:28px}.metric span{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.08em}.actions{display:flex;gap:12px;flex-wrap:wrap;margin:28px 0}.button{display:inline-block;padding:11px 16px;border-radius:12px;border:1px solid var(--line);background:#16243f;font-weight:700}.button.primary{background:#0ea5e9;color:white;border-color:#0ea5e9}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-top:24px}.card{background:rgba(17,27,49,.9);border:1px solid var(--line);border-radius:16px;padding:18px}.card h2{margin:0 0 8px;font-size:20px}.card p{color:var(--muted);margin:0}.contact{width:100%;max-height:560px;object-fit:contain;background:#070c16;border-radius:14px;border:1px solid var(--line);margin-top:18px}.meta{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:24px}.meta code{word-break:break-all;color:#c6d4ef}footer{margin-top:42px;padding-top:24px;border-top:1px solid var(--line);color:var(--muted)}@media(max-width:800px){.hero{grid-template-columns:1fr}.grid{grid-template-columns:1fr}.meta{grid-template-columns:1fr}}
CSS

index = <<~HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="Public community acceptance evidence for Rails 8 AI Image Processing API.">
<title>#{CGI.escapeHTML(title)}</title>
<style>#{css}</style>
</head>
<body>
<main class="wrap">
  <div class="eyebrow">Community Acceptance Kit</div>
  <section class="hero">
    <div>
      <h1>#{CGI.escapeHTML(title)}</h1>
      <p class="lead">Reproducible Ruby black-box acceptance evidence for authentication, deterministic image processing, BiRefNet background removal, MobileSAM prompt segmentation, validation, and visual review.</p>
      <div class="actions">
        <a class="button primary" href="report.html">Full technical report</a>
        <a class="button" href="report-compact.html">Compact report</a>
        <a class="button" href="gallery.html">Visual gallery</a>
      </div>
    </div>
    <aside class="panel">
      <div class="eyebrow">Acceptance status</div>
      <div class="status #{status_class}">#{status}</div>
      <div class="metrics">
        <div class="metric"><b class="pass">#{counts["PASS"].to_i}</b><span>Pass</span></div>
        <div class="metric"><b class="fail">#{counts["FAIL"].to_i}</b><span>Fail</span></div>
        <div class="metric"><b class="skip">#{counts["SKIP"].to_i}</b><span>Skip</span></div>
      </div>
    </aside>
  </section>

  <section class="grid">
    <article class="card"><h2>Ruby-native</h2><p>The public runners, fixture generator, report generator, and site builder are implemented in Ruby, with shell used only for orchestration.</p></article>
    <article class="card"><h2>Visual evidence</h2><p>Inputs and generated outputs are embedded into self-contained reports that reviewers can open directly without a web server.</p></article>
    <article class="card"><h2>Integrity</h2><p>Fixtures, evidence, reports, and deployable site files can be verified with SHA-256 checksums.</p></article>
    <article class="card"><h2>Contract fixture, not benchmark</h2><p>The synthetic scene verifies API behavior and prompt mechanics. It is not an accuracy or semantic-quality benchmark for BiRefNet or MobileSAM.</p></article>
  </section>

  #{contact_uri ? %(<img class="contact" src="#{contact_uri}" alt="Acceptance fixture contact sheet">) : ""}

  <section class="panel meta">
    <div><div class="eyebrow">Target</div><code>#{CGI.escapeHTML(target.to_s.empty? ? "preview / not yet bound to a live target" : target.to_s)}</code></div>
    <div><div class="eyebrow">Generated</div><code>#{CGI.escapeHTML(generated)}</code></div>
    <div><div class="eyebrow">Acceptance kit</div><a href="#{CGI.escapeHTML(source_url)}">#{CGI.escapeHTML(source_url)}</a></div>
    <div><div class="eyebrow">Application source</div><a href="#{CGI.escapeHTML(application_url)}">#{CGI.escapeHTML(application_url)}</a></div>
  </section>

  <footer>
    Static build mode: <code>#{mode}</code>. This site contains no runtime credentials, access tokens, refresh tokens, or application secrets.
  </footer>
</main>
</body>
</html>
HTML

File.write(File.join(out, "index.html"), index)
File.write(File.join(out, "404.html"), index.sub("<title>", "<title>Acceptance Site — "))
File.write(File.join(out, "robots.txt"), "User-agent: *\nAllow: /\n")

hashable = Dir.glob(File.join(out, "*")).select { |path| File.file?(path) && File.basename(path) != "SHA256SUMS" }.sort
File.open(File.join(out, "SHA256SUMS"), "w") do |f|
  hashable.each { |path| f.puts "#{Digest::SHA256.file(path).hexdigest}  #{File.basename(path)}" }
end

puts "STATIC_SITE_BUILD=PASS"
puts "OUT=#{out}"
puts "STATUS=#{status}"
puts "FILES=#{Dir.glob(File.join(out, "*")).count { |p| File.file?(p) }}"
puts "INDEX_SHA256=#{Digest::SHA256.file(File.join(out, "index.html")).hexdigest}"
