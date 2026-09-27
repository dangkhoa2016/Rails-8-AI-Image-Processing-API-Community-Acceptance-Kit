# frozen_string_literal: true
STDOUT.sync = true
STDERR.sync = true

require "json"
require "optparse"
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
refresh_token = nil

parse = ->(response) { JSON.parse(response.body) rescue {} }

login = lambda do |label|
  response = client.request(
    :post,
    "/users/sign_in",
    json: { user: { email: options[:email], password: options[:password] } }
  )
  next false unless ev.expect(label, response, 200)

  body = parse.call(response)
  client.token = body["token"]
  refresh_token = body["refresh_token"]
  ok = !client.token.to_s.empty? && !refresh_token.to_s.empty? && body["user"].is_a?(Hash)
  ev.record("#{label}.tokens", ok ? "PASS" : "FAIL", "access token + refresh token + user present")
  ok
end

begin
  ev.expect("refresh.missing", client.request(:post, "/users/tokens/refresh"), 401)
  ev.expect(
    "refresh.invalid",
    client.request(:post, "/users/tokens/refresh", headers: { "X-Refresh-Token" => "invalid-community-e2e" }),
    401
  )

  raise "initial login failed" unless login.call("auth.login")

  old_refresh = refresh_token
  response = client.request(
    :post,
    "/users/tokens/refresh",
    headers: { "X-Refresh-Token" => old_refresh }
  )

  if ev.expect("refresh.rotate", response, 200)
    body = parse.call(response)
    new_access = body["access_token"]
    new_refresh = body["refresh_token"]
    ok = !new_access.to_s.empty? && !new_refresh.to_s.empty? && new_refresh != old_refresh
    ev.record("refresh.rotated_values", ok ? "PASS" : "FAIL", "refresh token changed")
    client.token = new_access
    refresh_token = new_refresh
  end

  ev.expect(
    "refresh.reuse_detected",
    client.request(:post, "/users/tokens/refresh", headers: { "X-Refresh-Token" => old_refresh }),
    401
  )

  raise "re-login after reuse failed" unless login.call("auth.relogin_after_reuse")

  current_access = client.token
  response = client.request(
    :delete,
    "/users/sign_out",
    auth: true,
    headers: { "X-Refresh-Token" => refresh_token }
  )
  ev.expect("auth.sign_out", response, [200, 422])

  client.token = current_access
  ev.expect("auth.revoked_access_denied", client.request(:get, "/user/profile", auth: true), [401, 422])

  ev.record(
    "account.password_mutation",
    "SKIP",
    "kept out of the public black-box kit; covered by the Rails account-management test suite"
  )
rescue StandardError => e
  ev.record("runner.exception", "FAIL", "#{e.class}: #{e.message}")
  warn e.backtrace.join("\n")
end

ok = ev.finish({ "target_label" => ENV.fetch("E2E_TARGET_LABEL", "runtime-configured deployment"), "suite" => "auth_lifecycle", "generated_at_utc" => Time.now.utc.iso8601 }, filename: "auth-summary.json")
exit(ok ? 0 : 1)
