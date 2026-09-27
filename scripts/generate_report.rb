# frozen_string_literal: true

require "base64"
require "cgi"
require "digest"
require "erb"
require "json"
require "optparse"
require "pathname"
require "time"

options = {}
OptionParser.new do |o|
  o.on("--evidence DIR") { |v| options[:evidence] = File.expand_path(v) }
  o.on("--out DIR") { |v| options[:out] = File.expand_path(v) }
  o.on("--title TITLE") { |v| options[:title] = v }
  o.on("--preview") { options[:preview] = true }
end.parse!

root = File.expand_path("..", __dir__)
assets_root = File.join(root, "assets")
evidence = options[:evidence]
out_dir = options[:out] || evidence || File.join(root, "report-preview")
Dir.mkdir(out_dir) unless Dir.exist?(out_dir)

def data_uri(path)
  return nil unless path && File.file?(path)
  ext = File.extname(path).downcase
  mime = {
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".webp" => "image/webp",
    ".svg" => "image/svg+xml"
  }.fetch(ext, "application/octet-stream")
  "data:#{mime};base64,#{Base64.strict_encode64(File.binread(path))}"
end

def safe_json(path)
  return nil unless path && File.file?(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError
  nil
end

def status_class(status)
  case status.to_s.upcase
  when "PASS" then "pass"
  when "FAIL" then "fail"
  when "SKIP" then "skip"
  else "neutral"
  end
end

def collect_images(dir)
  return [] unless dir && Dir.exist?(dir)
  Dir.glob(File.join(dir, "*.{png,jpg,jpeg,webp}")).sort.map do |path|
    meta = safe_json(path.sub(/.[^.]+z/, ".json")) || {}
    {
      name: File.basename(path),
      path: path,
      uri: data_uri(path),
      meta: meta
    }
  end
end

summary = evidence ? safe_json(File.join(evidence, "summary.json")) : nil
auth_summary = evidence ? safe_json(File.join(evidence, "auth-summary.json")) : nil
rate_summary = evidence ? safe_json(File.join(evidence, "rate-limits-summary.json")) : nil
visual_review = evidence ? safe_json(File.join(evidence, "visual-review.json")) : nil

if options[:preview] || summary.nil?
  summary = {
    "target_label" => "preview / no live target",
    "generated_at_utc" => Time.now.utc.iso8601,
    "counts" => { "PASS" => 34, "FAIL" => 0, "SKIP" => 2 },
    "results" => [
      { "name" => "public.up", "status" => "PASS", "detail" => "HTTP 200" },
      { "name" => "auth.login", "status" => "PASS", "detail" => "HTTP 200" },
      { "name" => "images.capabilities", "status" => "PASS", "detail" => "HTTP 200" },
      { "name" => "process.resize_to_fit", "status" => "PASS", "detail" => "HTTP 200" },
      { "name" => "process.metadata_stripped", "status" => "PASS", "detail" => "orientation metadata absent" },
      { "name" => "remove_background.png", "status" => "PASS", "detail" => "HTTP 200" },
      { "name" => "segment.point_positive", "status" => "PASS", "detail" => "HTTP 200" },
      { "name" => "segment.box", "status" => "PASS", "detail" => "HTTP 200" },
      { "name" => "admin.full_admin_flows", "status" => "SKIP", "detail" => "admin authority required" },
      { "name" => "email.confirmation_flow", "status" => "SKIP", "detail" => "mail capture required" }
    ]
  }
end

inputs = Dir.glob(File.join(assets_root, "input", "*.{png,jpg,jpeg,webp}")).sort.map do |path|
  { name: File.basename(path), path: path, uri: data_uri(path) }
end
outputs = collect_images(evidence)
prompts = safe_json(File.join(assets_root, "prompts.json")) || {}
contact_sheet = data_uri(File.join(assets_root, "input-contact-sheet.jpg"))
person_input = inputs.find { |img| img[:name] == "person-scene-768x768.png" }
person_uri = person_input && person_input[:uri]

all_results = Array(summary["results"]) + Array(auth_summary && auth_summary["results"]) + Array(rate_summary && rate_summary["results"])
counts = all_results.each_with_object(Hash.new(0)) { |r, h| h[r["status"].to_s] += 1 }
counts = summary["counts"] if all_results.empty?

groups = {
  "Authentication & Authorization" => /^(auth.|profile.|authorization.|refresh.|account.)/,
  "Image Processing" => /^process./,
  "BiRefNet" => /^remove_background/,
  "MobileSAM" => /^segment./,
  "Public / Capabilities" => /^(public.|unauth.|images.capabilities|capabilities.)/,
  "Other" => //
}

grouped = groups.transform_values { [] }
all_results.each do |row|
  key = groups.keys.find { |name| groups[name].match?(row["name"].to_s) } || "Other"
  grouped[key] << row
end

title = options[:title] || "Rails 8 AI Image Processing API — Community E2E Acceptance"
preview = options[:preview] || evidence.nil?
target_label = summary["target_label"].to_s
target_label = preview ? "preview / no live target" : "runtime-configured deployment" if target_label.empty?
generated = summary["generated_at_utc"].to_s

css = <<~CSS
  :root{--bg:#0b1020;--panel:#121a2d;--panel2:#19233a;--text:#eef3ff;--muted:#9fb0cf;--pass:#4ade80;--fail:#fb7185;--skip:#fbbf24;--line:#2b3a58;--accent:#7dd3fc}
  *{box-sizing:border-box} body{margin:0;background:linear-gradient(180deg,#0b1020,#0d1325 45%,#0a0f1d);color:var(--text);font:15px/1.55 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
  .wrap{max-width:1280px;margin:auto;padding:32px 22px 64px}.hero{display:flex;gap:20px;justify-content:space-between;align-items:flex-start;margin-bottom:24px}
  h1{font-size:clamp(28px,4vw,48px);line-height:1.05;margin:0 0 12px}.sub{color:var(--muted);max-width:820px}.badge{padding:7px 12px;border:1px solid var(--line);border-radius:999px;background:#0f172a;color:var(--muted);white-space:nowrap}
  .grid{display:grid;grid-template-columns:repeat(12,1fr);gap:16px}.card{background:rgba(18,26,45,.93);border:1px solid var(--line);border-radius:16px;padding:18px}.span4{grid-column:span 4}.span6{grid-column:span 6}.span8{grid-column:span 8}.span12{grid-column:span 12}
  .metric{font-size:34px;font-weight:750}.label{color:var(--muted);font-size:13px;text-transform:uppercase;letter-spacing:.08em}.pass{color:var(--pass)}.fail{color:var(--fail)}.skip{color:var(--skip)}.neutral{color:var(--muted)}
  table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:10px;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.06em}
  .gallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px}.shot{background:#0d1426;border:1px solid var(--line);border-radius:14px;overflow:hidden}.shot img{width:100%;height:220px;object-fit:contain;background:#090f1d}.shot .meta{padding:12px}.shot code{word-break:break-all;font-size:11px;color:var(--muted)}
  .pill{display:inline-block;padding:3px 8px;border-radius:999px;font-size:12px;font-weight:700}.pill.pass{background:#123523}.pill.fail{background:#3c1520}.pill.skip{background:#3d3010}
  code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}.small{font-size:12px;color:var(--muted)}.prompt{display:flex;gap:12px;flex-wrap:wrap}.prompt code{background:#0a1120;padding:10px;border-radius:10px;border:1px solid var(--line)}
  .prompt-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px;margin-bottom:16px}.prompt-card{background:#0d1426;border:1px solid var(--line);border-radius:14px;overflow:hidden}.prompt-viz{position:relative;aspect-ratio:1/1;background:#09101d}.prompt-viz img{width:100%;height:100%;object-fit:contain;display:block}.point{position:absolute;width:18px;height:18px;border-radius:50%;transform:translate(-50%,-50%);border:3px solid #fff;box-shadow:0 0 0 3px rgba(0,0,0,.35)}.point.pos{background:#22c55e}.point.neg{background:#ef4444}.boxmark{position:absolute;border:4px solid #38bdf8;box-shadow:0 0 0 2px rgba(0,0,0,.35) inset}.prompt-caption{padding:12px}.legend-dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px}.legend-dot.pos{background:#22c55e}.legend-dot.neg{background:#ef4444}.legend-box{display:inline-block;width:14px;height:10px;border:2px solid #38bdf8;margin-right:6px}
  @media(max-width:800px){.span4,.span6,.span8{grid-column:span 12}.hero{flex-direction:column}}
CSS

template = <<~'ERB'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title><%= CGI.escapeHTML(title) %></title>
<style><%= css %></style>
</head>
<body>
<div class="wrap">
  <section class="hero">
    <div>
      <h1><%= CGI.escapeHTML(title) %></h1>
      <div class="sub">Black-box acceptance evidence for authentication, deterministic image operations, BiRefNet background removal, MobileSAM prompt segmentation, validation, and integrity artifacts.</div>
    </div>
    <div class="badge"><%= preview ? "PREVIEW / NO LIVE EVIDENCE" : "LIVE EVIDENCE" %></div>
  </section>

  <div class="grid">
    <div class="card span4"><div class="label">PASS</div><div class="metric pass"><%= counts["PASS"].to_i %></div></div>
    <div class="card span4"><div class="label">FAIL</div><div class="metric fail"><%= counts["FAIL"].to_i %></div></div>
    <div class="card span4"><div class="label">SKIP</div><div class="metric skip"><%= counts["SKIP"].to_i %></div></div>

    <div class="card span8">
      <div class="label">Target</div>
      <div><code><%= CGI.escapeHTML(target_label) %></code></div>
      <div class="small">Generated: <%= CGI.escapeHTML(generated) %></div>
    </div>
    <div class="card span4">
      <div class="label">Evidence mode</div>
      <div class="metric" style="font-size:22px"><%= preview ? "Layout preview" : "Acceptance run" %></div>
    </div>

    <% grouped.each do |name, rows| %>
      <% next if rows.empty? %>
      <section class="card span12">
        <h2><%= CGI.escapeHTML(name) %></h2>
        <table>
          <thead><tr><th>Status</th><th>Check</th><th>Detail</th></tr></thead>
          <tbody>
          <% rows.each do |row| %>
            <tr>
              <td><span class="pill <%= status_class(row["status"]) %>"><%= CGI.escapeHTML(row["status"].to_s) %></span></td>
              <td><code><%= CGI.escapeHTML(row["name"].to_s) %></code></td>
              <td><%= CGI.escapeHTML(row["detail"].to_s) %></td>
            </tr>
          <% end %>
          </tbody>
        </table>
      </section>
    <% end %>

    <section class="card span12">
      <h2>Scope and interpretation</h2>
      <p class="small">These images are synthetic contract fixtures designed to verify endpoint behavior, encoding, validation, alpha handling, prompt mechanics, and evidence integrity. They are <strong>not</strong> a semantic-quality or accuracy benchmark for BiRefNet or MobileSAM. Visual outputs should therefore be interpreted as contract evidence, not as model-quality claims.</p>
    </section>

    <section class="card span12">
      <h2>Input fixture gallery</h2>
      <% if contact_sheet %><img src="<%= contact_sheet %>" style="width:100%;max-height:620px;object-fit:contain;border-radius:12px;background:#09101d"><% end %>
      <div class="gallery" style="margin-top:14px">
        <% inputs.each do |img| %>
          <div class="shot"><img src="<%= img[:uri] %>"><div class="meta"><strong><%= CGI.escapeHTML(img[:name]) %></strong></div></div>
        <% end %>
      </div>
    </section>

    <section class="card span12">
      <h2>MobileSAM prompt authority</h2>
      <% if person_uri %>
      <div class="prompt-grid">
        <% if prompts["positive_point"] %>
        <% p = prompts["positive_point"] %>
        <div class="prompt-card">
          <div class="prompt-viz">
            <img src="<%= person_uri %>">
            <span class="point pos" style="left:<%= p["x"].to_f / 768.0 * 100 %>%;top:<%= p["y"].to_f / 768.0 * 100 %>%"></span>
          </div>
          <div class="prompt-caption"><span class="legend-dot pos"></span><strong>Positive point</strong><br><code><%= CGI.escapeHTML(JSON.generate(p)) %></code></div>
        </div>
        <% end %>

        <% if prompts["negative_point"] %>
        <% p = prompts["negative_point"] %>
        <div class="prompt-card">
          <div class="prompt-viz">
            <img src="<%= person_uri %>">
            <span class="point neg" style="left:<%= p["x"].to_f / 768.0 * 100 %>%;top:<%= p["y"].to_f / 768.0 * 100 %>%"></span>
          </div>
          <div class="prompt-caption"><span class="legend-dot neg"></span><strong>Negative point</strong><br><code><%= CGI.escapeHTML(JSON.generate(p)) %></code></div>
        </div>
        <% end %>

        <% if prompts["box"] %>
        <% p = prompts["box"] %>
        <div class="prompt-card">
          <div class="prompt-viz">
            <img src="<%= person_uri %>">
            <span class="boxmark" style="left:<%= p["x0"].to_f / 768.0 * 100 %>%;top:<%= p["y0"].to_f / 768.0 * 100 %>%;width:<%= (p["x1"].to_f-p["x0"].to_f) / 768.0 * 100 %>%;height:<%= (p["y1"].to_f-p["y0"].to_f) / 768.0 * 100 %>%"></span>
          </div>
          <div class="prompt-caption"><span class="legend-box"></span><strong>Bounding box</strong><br><code><%= CGI.escapeHTML(JSON.generate(p)) %></code></div>
        </div>
        <% end %>
      </div>
      <% end %>
    </section>

    <% if visual_review %>
    <section class="card span12">
      <h2>Human visual review</h2>
      <p class="small"><%= CGI.escapeHTML(visual_review["scope"].to_s) %></p>
      <table>
        <thead><tr><th>Area</th><th>Review result</th><th>Notes</th></tr></thead>
        <tbody>
        <% Array(visual_review["notes"]).each do |note| %>
          <tr>
            <td><strong><%= CGI.escapeHTML(note["area"].to_s) %></strong></td>
            <td><code><%= CGI.escapeHTML(note["result"].to_s) %></code></td>
            <td><%= CGI.escapeHTML(note["detail"].to_s) %></td>
          </tr>
        <% end %>
        </tbody>
      </table>
    </section>
    <% end %>

    <% unless outputs.empty? %>
    <section class="card span12">
      <h2>Generated outputs</h2>
      <div class="gallery">
        <% outputs.each do |img| %>
          <div class="shot">
            <img src="<%= img[:uri] %>">
            <div class="meta">
              <strong><%= CGI.escapeHTML(img[:name]) %></strong><br>
              <% if img[:meta]["processing_ms"] %><span class="small">processing: <%= CGI.escapeHTML(img[:meta]["processing_ms"].to_s) %> ms</span><br><% end %>
              <% if img[:meta]["sha256"] %><code><%= CGI.escapeHTML(img[:meta]["sha256"]) %></code><% end %>
            </div>
          </div>
        <% end %>
      </div>
    </section>
    <% end %>
  </div>
</div>
</body>
</html>
ERB

full_html = ERB.new(template).result(binding)
File.write(File.join(out_dir, "report.html"), full_html)

compact_template = <<~'ERB'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title><%= CGI.escapeHTML(title) %> — Compact</title><style><%= css %></style></head>
<body><div class="wrap"><section class="hero"><div><h1><%= CGI.escapeHTML(title) %></h1><div class="sub"><code><%= CGI.escapeHTML(target_label) %></code></div></div><div class="badge"><%= preview ? "PREVIEW" : "LIVE" %></div></section>
<div class="grid"><div class="card span4"><div class="label">PASS</div><div class="metric pass"><%= counts["PASS"].to_i %></div></div><div class="card span4"><div class="label">FAIL</div><div class="metric fail"><%= counts["FAIL"].to_i %></div></div><div class="card span4"><div class="label">SKIP</div><div class="metric skip"><%= counts["SKIP"].to_i %></div></div>
<div class="card span12"><h2>Highlights</h2><table><% all_results.first(18).each do |r| %><tr><td><span class="pill <%= status_class(r["status"]) %>"><%= CGI.escapeHTML(r["status"].to_s) %></span></td><td><code><%= CGI.escapeHTML(r["name"].to_s) %></code></td><td><%= CGI.escapeHTML(r["detail"].to_s) %></td></tr><% end %></table></div>
<% if contact_sheet %><div class="card span12"><h2>Fixture contact sheet</h2><img src="<%= contact_sheet %>" style="width:100%;max-height:620px;object-fit:contain"></div><% end %>
</div></div></body></html>
ERB
File.write(File.join(out_dir, "report-compact.html"), ERB.new(compact_template).result(binding))

gallery_template = <<~'ERB'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Acceptance Gallery</title><style><%= css %></style></head>
<body><div class="wrap"><h1>Acceptance Gallery</h1><div class="sub">Self-contained visual gallery for community review.</div>
<h2>Inputs</h2><div class="gallery"><% inputs.each do |img| %><div class="shot"><img src="<%= img[:uri] %>"><div class="meta"><strong><%= CGI.escapeHTML(img[:name]) %></strong></div></div><% end %></div>
<% unless outputs.empty? %><h2>Outputs</h2><div class="gallery"><% outputs.each do |img| %><div class="shot"><img src="<%= img[:uri] %>"><div class="meta"><strong><%= CGI.escapeHTML(img[:name]) %></strong></div></div><% end %></div><% end %>
</div></body></html>
ERB
File.write(File.join(out_dir, "gallery.html"), ERB.new(gallery_template).result(binding))

%w[report.html report-compact.html gallery.html].each do |name|
  path = File.join(out_dir, name)
  puts "#{name}	#{File.size(path)} bytes	sha256=#{Digest::SHA256.file(path).hexdigest}"
end
