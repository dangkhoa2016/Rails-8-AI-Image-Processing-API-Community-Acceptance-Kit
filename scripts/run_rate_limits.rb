# frozen_string_literal: true
STDOUT.sync = true
STDERR.sync = true

require "json"
require "optparse"
require "securerandom"
require "time"
require_relative "http_support"

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
parse = ->(response) { JSON.parse(response.body) rescue {} }

begin
  ev.expect("rate_limit.public_up", client.request(:get, "/up"), 200)

  # Rack::Attack uses 60-second cache buckets. Always move into a fresh bucket
  # so functional/auth requests executed immediately before this suite cannot
  # contaminate sign-in or refresh-token throttle counts.
  wait_seconds = 62 - (Time.now.to_i % 60)
  puts "[INFO] rate_limit.fresh_window_wait: sleeping #{wait_seconds}s"
  sleep(wait_seconds)

  login = client.request(
    :post,
    "/users/sign_in",
    json: { user: { email: options[:email], password: options[:password] } }
  )
  if ev.expect("rate_limit.login", login, 200)
    body = parse.call(login)
    access = body["token"]
    auth_header = login["authorization"].to_s
    access = auth_header.sub(/\ABearer\s+/i, "") if access.to_s.empty? && auth_header.match?(/\ABearer\s+/i)
    client.token = access
    ev.record("rate_limit.login_access_token", access.to_s.empty? ? "FAIL" : "PASS", "access token available")
    ev.expect("rate_limit.profile", client.request(:get, "/user/profile", auth: true), 200) unless access.to_s.empty?
  end

  spoof_email = "community-spoof-#{Time.now.to_i}-#{SecureRandom.hex(4)}@example.invalid"
  spoof_body = { user: { email: spoof_email, password: "definitely-wrong" } }

  (11..14).each do |i|
    response = client.request(
      :post,
      "/users/sign_in",
      headers: { "X-Forwarded-For" => "198.51.100.#{i}" },
      json: spoof_body
    )
    if response.code.to_i == 429
      ev.record("rate_limit.spoof_request_#{i}", "FAIL", "throttled too early")
    else
      ev.record("rate_limit.spoof_request_#{i}", "PASS", "HTTP #{response.code}; not throttled early")
    end
  end

  fifth = client.request(
    :post,
    "/users/sign_in",
    headers: { "X-Forwarded-For" => "198.51.100.15" },
    json: spoof_body
  )
  ev.expect("rate_limit.spoof_resistance_fifth", fifth, 429)

  early_refresh_failure = false
  (1..20).each do |i|
    response = client.request(
      :post,
      "/users/tokens/refresh",
      headers: { "X-Refresh-Token" => "invalid-#{i}-#{SecureRandom.hex(6)}" }
    )
    if response.code.to_i == 429
      early_refresh_failure = true
      ev.record("rate_limit.refresh_#{i}", "FAIL", "throttled before request 21")
      break
    end
  end
  ev.record("rate_limit.refresh_first_20", "PASS", "requests 1-20 stayed below throttle") unless early_refresh_failure

  unless early_refresh_failure
    response = client.request(
      :post,
      "/users/tokens/refresh",
      headers: { "X-Refresh-Token" => "invalid-21-#{SecureRandom.hex(6)}" }
    )
    ev.expect("rate_limit.refresh_21", response, 429)
  end
rescue StandardError => e
  ev.record("runner.exception", "FAIL", "#{e.class}: #{e.message}")
  warn e.backtrace.join("\n")
end

ok = ev.finish({ "target_label" => ENV.fetch("E2E_TARGET_LABEL", "runtime-configured deployment"), "suite" => "rate_limits", "generated_at_utc" => Time.now.utc.iso8601 }, filename: "rate-limits-summary.json")
exit(ok ? 0 : 1)
