class VshElasticsearch5 < Formula
  desc "Distributed search & analytics engine"
  homepage "https://www.elastic.co/products/elasticsearch"
  url "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-5.6.16.tar.gz"
  sha256 "6b035a59337d571ab70cea72cc55225c027ad142fbb07fd8984e54261657c77f"
  license "Apache-2.0"
  revision 3

  bottle do
    root_url "https://github.com/valet-sh/homebrew-core/releases/download/bottles"
    rebuild 3
    sha256 "56d5b22fb9f2b1dc58566b629ed60e53c1f29b8655d8892cbc01fa9f8f3121bf" => :catalina
    sha256 "2424c26e91253868168289ea00becf17fdd48beffacdd3be5ec1285252aec39b" => :mojave

  end

  depends_on :java => "1.8"

  def cluster_name
    "elasticsearch_#{ENV["USER"]}"
  end

  def install
    # Remove Windows files
    rm_f Dir["bin/*.bat"]
    rm_f Dir["bin/*.exe"]

    # Install everything else into package directory
    libexec.install "bin", "config", "lib", "modules"

#    inreplace libexec/"bin/elasticsearch-env",
#              "if [ -z \"$ES_PATH_CONF\" ]; then ES_PATH_CONF=\"$ES_HOME\"/config; fi",
#              "if [ -z \"$ES_PATH_CONF\" ]; then ES_PATH_CONF=\"#{etc}/#{name}\"; fi"

    # Set up Elasticsearch for local development:
    inreplace "#{libexec}/config/elasticsearch.yml" do |s|
      # 1. Give the cluster a unique name
      s.gsub!(/#\s*cluster\.name: .*/, "cluster.name: #{cluster_name}")
      s.gsub!(/#\s*network\.host: .*/, "network.host: 127.0.0.1")
      s.gsub!(/#\s*http\.port: .*/, "http.port: 9205")

      # 2. Configure paths
      s.sub!(%r{#\s*path\.data: /path/to.+$}, "path.data: #{var}/lib/#{name}/")
      s.sub!(%r{#\s*path\.logs: /path/to.+$}, "path.logs: #{var}/log/#{name}/")

    end

    config_file = "#{libexec}/config/elasticsearch.yml"
    open(config_file, "a") { |f| f.puts "transport.type: local\n" }

    # Move config files into etc
    (etc/"#{name}").install Dir[libexec/"config/*"]
    (libexec/"config").rmtree

    (libexec/"bin/elasticsearch-plugin-update").write <<~EOS
        #!/bin/bash

        export JAVA_HOME="$(/usr/libexec/java_home -v 1.8)"

        base_dir=$(dirname $0)
        PLUGIN_BIN=${base_dir}/elasticsearch-plugin

        for plugin in $(${PLUGIN_BIN} list); do
            "${PLUGIN_BIN}" remove "${plugin}"
            "${PLUGIN_BIN}" install "${plugin}"
        done
    EOS

    chmod 0755, libexec/"bin/elasticsearch-plugin-update"

    inreplace libexec/"bin/elasticsearch",
              "CDPATH=\"\"",
              "JAVA_HOME=\"/Library/Java/JavaVirtualMachines/adoptopenjdk-8.jdk/Contents/Home\"\nCDPATH=\"\""
  end

  def post_install
    # Make sure runtime directories exist
    (var/"lib/#{name}").mkpath
    (var/"log/#{name}").mkpath
    ln_s etc/"#{name}", libexec/"config" unless (libexec/"config").exist?
    (var/"#{name}/plugins").mkpath
    ln_s var/"#{name}/plugins", libexec/"plugins" unless (libexec/"plugins").exist?

    system libexec/"bin/elasticsearch-plugin-update"
  end

  def caveats
    <<~EOS
      Data:    #{var}/lib/#{name}/
      Logs:    #{var}/log/#{name}/#{cluster_name}.log
      Plugins: #{var}/#{name}/plugins/
      Config:  #{etc}/#{name}/
    EOS
  end

  plist_options :manual => "vsh-elasticsearch5"

  def plist
    <<~EOS
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
        <dict>
          <key>KeepAlive</key>
          <false/>
          <key>Label</key>
          <string>#{plist_name}</string>
          <key>ProgramArguments</key>
          <array>
            <string>#{opt_libexec}/bin/elasticsearch</string>
          </array>
          <key>EnvironmentVariables</key>
          <dict>
          </dict>
          <key>RunAtLoad</key>
          <true/>
          <key>WorkingDirectory</key>
          <string>#{var}</string>
          <key>StandardErrorPath</key>
          <string>#{var}/log/#{name}/elasticsearch.log</string>
          <key>StandardOutPath</key>
          <string>#{var}/log/#{name}/elasticsearch.log</string>
        </dict>
      </plist>
    EOS
  end

  test do
    assert_includes(stable.url, "-oss-")

    port = free_port
    system "#{bin}/elasticsearch-plugin", "list"
    pid = testpath/"pid"
    begin
      system "#{bin}/elasticsearch", "-d", "-p", pid, "-Epath.data=#{testpath}/data", "-Ehttp.port=#{port}"
      sleep 10
      system "curl", "-XGET", "localhost:#{port}/"
    ensure
      Process.kill(9, pid.read.to_i)
    end

    port = free_port
    (testpath/"config/elasticsearch.yml").write <<~EOS
      path.data: #{testpath}/data
      path.logs: #{testpath}/logs
      node.name: test-es-path-conf
      http.port: #{port}
    EOS

    cp etc/"elasticsearch/jvm.options", "config"
    cp etc/"elasticsearch/log4j2.properties", "config"

    ENV["ES_PATH_CONF"] = testpath/"config"
    pid = testpath/"pid"
    begin
      system "#{bin}/elasticsearch", "-d", "-p", pid
      sleep 10
      system "curl", "-XGET", "localhost:#{port}/"
      output = shell_output("curl -s -XGET localhost:#{port}/_cat/nodes")
      assert_match "test-es-path-conf", output
    ensure
      Process.kill(9, pid.read.to_i)
    end
  end
end
