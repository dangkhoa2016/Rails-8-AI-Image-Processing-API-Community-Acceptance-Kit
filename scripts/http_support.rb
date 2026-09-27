# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "digest"
require "securerandom"
require "fileutils"

module CommunityE2E
  class Client
    attr_accessor :token
    attr_reader :base_url

    def initialize(base_url)
      @base_url = base_url.sub(%r{/+$}, "")
      @token = nil
    end

    def request(method, path, auth: false, headers: {}, json: nil, form: nil, timeout: 120)
      uri = URI.join("#{@base_url}/", path.sub(%r{^/}, ""))
      klass = Net::HTTP.const_get(method.to_s.capitalize)
      req = klass.new(uri)
      headers.each { |k, v| req[k] = v }
      req["Authorization"] = "Bearer #{@token}" if auth && @token

      if json
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(json)
      elsif form
        req.set_form_data(form)
      end

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: 30, read_timeout: timeout) { |http| http.request(req) }
    end

    def multipart(path, image_path:, fields:, auth: true, timeout: 300)
      uri = URI.join("#{@base_url}/", path.sub(%r{^/}, ""))
      boundary = "----rails8-e2e-#{SecureRandom.hex(12)}"
      body = +"".b

      fields.each do |name, value|
        body << "--#{boundary}\r\n"
        body << %(Content-Disposition: form-data; name="#{name}"\r\n\r\n)
        body << value.to_s
        body << "\r\n"
      end

      filename = File.basename(image_path)
      body << "--#{boundary}\r\n"
      body << %(Content-Disposition: form-data; name="image"; filename="#{filename}"\r\n)
      body << "Content-Type: application/octet-stream\r\n\r\n"
      body << File.binread(image_path)
      body << "\r\n--#{boundary}--\r\n"

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{@token}" if auth && @token
      req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      req.body = body

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: 30, read_timeout: timeout) { |http| http.request(req) }
    end
  end

  class Evidence
    attr_reader :rows

    def initialize(out_dir)
      @out = File.expand_path(out_dir)
      FileUtils.mkdir_p(@out)
      @rows = []
    end

    def record(name, status, detail = "")
      @rows << { "name" => name, "status" => status, "detail" => detail }
      puts "[#{status}] #{name}: #{detail}"
    end

    def expect(name, response, codes)
      expected = Array(codes).map(&:to_i)
      ok = expected.include?(response.code.to_i)
      record(name, ok ? "PASS" : "FAIL", "HTTP #{response.code}")
      warn("  body: #{response.body.to_s.byteslice(0, 500)}") unless ok
      ok
    end

    def save_response(label, response)
      type = response["content-type"].to_s.split(";").first
      ext = { "image/png" => "png", "image/jpeg" => "jpg", "image/webp" => "webp" }.fetch(type, "bin")
      path = File.join(@out, "#{label}.#{ext}")
      File.binwrite(path, response.body)
      meta = {
        "file" => File.basename(path),
        "bytes" => File.size(path),
        "sha256" => Digest::SHA256.file(path).hexdigest,
        "content_type" => type,
        "cache_control" => response["cache-control"],
        "x_width" => response["x-image-width"],
        "x_height" => response["x-image-height"],
        "x_format" => response["x-image-format"],
        "processing_ms" => response["x-processing-time-ms"]
      }
      File.write(File.join(@out, "#{label}.json"), JSON.pretty_generate(meta) + "\n")
      [path, meta]
    end

    def finish(extra = {}, filename: "summary.json")
      counts = @rows.each_with_object(Hash.new(0)) { |r, h| h[r["status"]] += 1 }
      summary = extra.merge("counts" => counts, "results" => @rows)
      File.write(File.join(@out, filename), JSON.pretty_generate(summary) + "\n")
      sums = Dir.glob(File.join(@out, "*")).select { |p| File.file?(p) && File.basename(p) != "SHA256SUMS" }.sort
      File.open(File.join(@out, "SHA256SUMS"), "w") do |f|
        sums.each { |p| f.puts "#{Digest::SHA256.file(p).hexdigest}  #{File.basename(p)}" }
      end
      puts "SUMMARY #{JSON.generate(counts)}"
      counts["FAIL"].to_i.zero?
    end
  end
end
