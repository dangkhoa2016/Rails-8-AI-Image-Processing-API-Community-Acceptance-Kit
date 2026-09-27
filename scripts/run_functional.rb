# frozen_string_literal: true
STDOUT.sync = true
STDERR.sync = true

require "json"
require "optparse"
require "open3"
require "time"
require_relative "http_support"

root = File.expand_path("..", __dir__)
input_dir = File.join(root, "assets", "input")

options = {
  base_url: ENV["E2E_BASE_URL"],
  email: ENV["E2E_EMAIL"],
  password: ENV["E2E_PASSWORD"]
}
OptionParser.new do |o|
  o.on("--base-url URL") { |v| options[:base_url] = v }
  o.on("--email EMAIL") { |v| options[:email] = v }
  o.on("--password PASSWORD") { |v| options[:password] = v }
  o.on("--out DIR") { |v| options[:out] = v }
end.parse!
abort "missing --base-url/--email/--password/--out" unless options.values_at(:base_url, :email, :password, :out).all?

client = CommunityE2E::Client.new(options[:base_url])
ev = CommunityE2E::Evidence.new(options[:out])

json_body = ->(response) { JSON.parse(response.body) rescue {} }

login = lambda do |label = "auth.login"|
  response = client.request(
    :post,
    "/users/sign_in",
    json: { user: { email: options[:email], password: options[:password] } }
  )
  next false unless ev.expect(label, response, 200)

  body = json_body.call(response)
  client.token = body["token"]
  user = body["user"]
  ok = !client.token.to_s.empty? && user.is_a?(Hash)
  ev.record("#{label}.credentials", ok ? "PASS" : "FAIL", "JWT and user present")
  options[:user] = user
  ok
end

rgb = File.join(input_dir, "rgb-gradient-640x480.png")
alpha = File.join(input_dir, "alpha-shapes-512x512.png")
person = File.join(input_dir, "person-scene-768x768.png")
exif_fixture = File.join(input_dir, "exif-orientation-480x640.jpg")
corrupt = File.join(input_dir, "corrupt-not-an-image.jpg")

begin
  ev.expect("public.up", client.request(:get, "/up"), 200)
  ev.expect("unauth.capabilities", client.request(:get, "/images/capabilities"), [401, 422])
  ev.expect("unauth.profile", client.request(:get, "/user/profile"), [401, 422])
  ev.expect(
    "unauth.process",
    client.multipart("/images/process", image_path: rgb, fields: { "operations" => "[]" }, auth: false),
    401
  )
  ev.expect(
    "auth.invalid_password",
    client.request(:post, "/users/sign_in",
                   json: { user: { email: options[:email], password: "definitely-wrong" } }),
    401
  )

  raise "login failed" unless login.call

  %w[/user/profile /user/me /user/whoami].each do |path|
    response = client.request(:get, path, auth: true)
    key = path.split("/").last
    if ev.expect("profile.#{key}", response, 200)
      email = json_body.call(response).dig("user", "email").to_s
      ev.record("profile.identity.#{key}",
                email.casecmp?(options[:email]) ? "PASS" : "FAIL",
                "same authenticated email")
    end
  end

  ev.expect("authorization.users_index_regular_denied",
            client.request(:get, "/users", auth: true), [401, 403])

  user_id = options.dig(:user, "id").to_s
  ev.expect("authorization.self_show",
            client.request(:get, "/users/#{user_id}", auth: true), 200)

  response = client.request(:get, "/images/capabilities", auth: true)
  if ev.expect("images.capabilities", response, 200)
    body = json_body.call(response)
    expected_ops = %w[
      resize_to_fit resize_to_fill crop rotate flip grayscale brightness contrast
      saturation tint blur sharpen background
    ]
    {
      "capabilities.version" => body["version"] == "v1",
      "capabilities.operations" => body["operations"] == expected_ops,
      "capabilities.formats" => body["response_content_types"] == %w[image/png image/jpeg image/webp],
      "capabilities.ai_enabled" => body["ai_enabled"] == true,
      "capabilities.ai_operations" => body["ai_operations"] == %w[remove_background segment]
    }.each do |name, ok|
      ev.record(name, ok ? "PASS" : "FAIL", "contract check")
    end
  end

  cases = [
    ["resize_to_fit", rgb, [{ op: "resize_to_fit", width: 320, height: 320 }]],
    ["resize_to_fill", rgb, [{ op: "resize_to_fill", width: 320, height: 320 }]],
    ["crop", rgb, [{ op: "crop", left: 40, top: 30, width: 300, height: 240 }]],
    ["rotate", rgb, [{ op: "rotate", degrees: 90 }]],
    ["flip", rgb, [{ op: "flip", mode: "horizontal" }]],
    ["grayscale", rgb, [{ op: "grayscale" }]],
    ["brightness", rgb, [{ op: "brightness", amount: 0.15 }]],
    ["contrast", rgb, [{ op: "contrast", amount: 0.2 }]],
    ["saturation", rgb, [{ op: "saturation", amount: -0.35 }]],
    ["tint", rgb, [{ op: "tint", color: "#336699", strength: 0.4 }]],
    ["blur", rgb, [{ op: "blur", sigma: 1.5 }]],
    ["sharpen", rgb, [{ op: "sharpen", amount: 0.6 }]],
    ["background", alpha, [{ op: "background", color: "#F4E04D" }]]
  ]

  cases.each do |name, image, operations|
    response = client.multipart(
      "/images/process",
      image_path: image,
      fields: { "operations" => JSON.generate(operations), "format" => "png" },
      timeout: 120
    )
    next unless ev.expect("process.#{name}", response, 200)

    _path, meta = ev.save_response("process-#{name}", response)
    ok = meta["content_type"] == "image/png" &&
         meta["cache_control"].to_s.downcase.include?("no-store")
    ev.record("process.#{name}.headers", ok ? "PASS" : "FAIL", JSON.generate(meta))
  end

  mixed = [
    { op: "resize_to_fit", width: 420, height: 315 },
    { op: "rotate", degrees: 90 },
    { op: "brightness", amount: 0.1 },
    { op: "contrast", amount: 0.1 },
    { op: "saturation", amount: 0.1 },
    { op: "tint", color: "#336699", strength: 0.25 },
    { op: "blur", sigma: 1.0 },
    { op: "sharpen", amount: 0.4 }
  ]

  [["png", nil], ["jpeg", "88"], ["webp", "82"]].each do |format, quality|
    fields = { "operations" => JSON.generate(mixed), "format" => format }
    fields["quality"] = quality if quality
    response = client.multipart("/images/process", image_path: rgb, fields: fields, timeout: 120)
    ev.save_response("process-mixed-#{format}", response) if ev.expect("process.codec.#{format}", response, 200)
  end

  response = client.multipart(
    "/images/process",
    image_path: exif_fixture,
    fields: {
      "operations" => JSON.generate([{ op: "resize_to_fit", width: 640, height: 640 }]),
      "format" => "jpeg",
      "quality" => "90"
    },
    timeout: 120
  )
  if ev.expect("process.exif_orientation", response, 200)
    path, = ev.save_response("process-exif-stripped", response)
    header, = Open3.capture2e("vipsheader", "-a", path)
    clean = !header.match?(/Orientation|exif-ifd0-Orientation/i)
    ev.record("process.metadata_stripped", clean ? "PASS" : "FAIL", clean ? "orientation metadata absent" : "orientation metadata still present")
  end

  negatives = [
    ["process.missing_image", -> { client.request(:post, "/images/process", auth: true, form: { "operations" => "[]" }) }],
    ["process.malformed_operations", -> { client.multipart("/images/process", image_path: rgb, fields: { "operations" => "{" }) }],
    ["process.unsupported_operation", -> { client.multipart("/images/process", image_path: rgb, fields: { "operations" => JSON.generate([{ op: "explode" }]) }) }],
    ["process.png_quality_rejected", -> { client.multipart("/images/process", image_path: rgb, fields: { "operations" => JSON.generate([{ op: "grayscale" }]), "format" => "png", "quality" => "80" }) }],
    ["process.opaque_background_rejected", -> { client.multipart("/images/process", image_path: exif_fixture, fields: { "operations" => JSON.generate([{ op: "background", color: "#FFFFFF" }]) }) }],
    ["process.corrupt_image", -> { client.multipart("/images/process", image_path: corrupt, fields: { "operations" => JSON.generate([{ op: "grayscale" }]) }) }],
    ["process.invalid_tint", -> { client.multipart("/images/process", image_path: rgb, fields: { "operations" => JSON.generate([{ op: "tint", color: "blue", strength: 0.5 }]) }) }],
    ["process.invalid_blur", -> { client.multipart("/images/process", image_path: rgb, fields: { "operations" => JSON.generate([{ op: "blur", sigma: 21 }]) }) }]
  ]
  negatives.each { |name, call| ev.expect(name, call.call, 422) }

  [
    ["remove_background.png", { "output" => "transparent", "format" => "png" }],
    ["remove_background.webp", { "output" => "transparent", "format" => "webp", "quality" => "82", "feather" => "10" }],
    ["remove_background.background", { "output" => "transparent", "format" => "png", "background" => "#F4E04D", "feather" => "0" }]
  ].each do |name, fields|
    response = client.multipart("/images/remove-background", image_path: person, fields: fields, timeout: 300)
    ev.save_response(name.tr(".", "-"), response) if ev.expect(name, response, 200)
  end

  [
    ["remove_background.jpeg_rejected", { "format" => "jpeg" }],
    ["remove_background.output_rejected", { "output" => "mask" }],
    ["remove_background.feather_rejected", { "feather" => "21" }]
  ].each do |name, fields|
    ev.expect(name, client.multipart("/images/remove-background", image_path: person, fields: fields, timeout: 300), 422)
  end

  prompts = [
    ["segment.point_positive", { type: "point", x: 384, y: 350, label: 1 }],
    ["segment.point_negative", { type: "point", x: 70, y: 70, label: 0 }],
    ["segment.box", { type: "box", x0: 210, y0: 95, x1: 555, y1: 755 }]
  ]
  prompts.each do |name, prompt|
    response = client.multipart("/images/segment", image_path: person,
                                fields: { "prompt" => JSON.generate(prompt) }, timeout: 300)
    next unless ev.expect(name, response, 200)

    path, = ev.save_response(name.tr(".", "-"), response)
    min_out, = Open3.capture2e("vips", "min", path)
    max_out, = Open3.capture2e("vips", "max", path)
    min = min_out.to_f
    max = max_out.to_f
    ev.record("#{name}.mask_nontrivial", min != max ? "PASS" : "FAIL", "min=#{min} max=#{max}")
  end

  ev.expect("segment.malformed_prompt",
            client.multipart("/images/segment", image_path: person, fields: { "prompt" => "{" }, timeout: 300), 422)
  ev.expect("segment.output_rejected",
            client.multipart("/images/segment", image_path: person,
                             fields: { "prompt" => JSON.generate(prompts.first.last), "output" => "overlay" }, timeout: 300), 422)
  ev.expect("segment.invalid_label",
            client.multipart("/images/segment", image_path: person,
                             fields: { "prompt" => JSON.generate({ type: "point", x: 384, y: 350, label: 2 }) }, timeout: 300), 422)

  ev.record("admin.full_admin_flows", "SKIP", "regular-user credential; admin authority required")
  ev.record("email.confirmation_flow", "SKIP", "disposable inbox or mail-capture authority required")
rescue StandardError => e
  ev.record("runner.exception", "FAIL", "#{e.class}: #{e.message}")
  warn e.backtrace.join("\n")
end

ok = ev.finish({
  "target_label" => ENV.fetch("E2E_TARGET_LABEL", "runtime-configured deployment"),
  "generated_at_utc" => Time.now.utc.iso8601
})
exit(ok ? 0 : 1)
