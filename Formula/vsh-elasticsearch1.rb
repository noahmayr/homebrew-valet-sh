class VshElasticsearch1 < Formula
  desc "Distributed search & analytics engine"
  homepage "https://www.elastic.co/products/elasticsearch"
  url "https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-1.7.6.tar.gz"
  sha256 "78affc30353730ec245dad1f17de242a4ad12cf808eaa87dd878e1ca10ed77df"
  license "Apache-2.0"
  revision 30

  bottle do
    root_url "https://github.com/valet-sh/homebrew-core/releases/download/bottles"
    sha256 big_sur: "e8a0ff9e463f14d857ea584bee4b0ade0799dd4131e7cd05782706df7a18ecb3"
  end


  on_intel do
    depends_on "openjdk@8"
  end

  #depends_on cask: "homebrew/cask-versions/zulu8"

  def cluster_name
    "elasticsearch_#{ENV["USER"]}"
  end


  def install
    java_home = Hardware::CPU.arm? ? `/usr/libexec/java_home -v 1.8 -a arm64 -F 2>/dev/null || /usr/libexec/java_home -v 1.8 -F` : "#{Formula['openjdk@8'].opt_libexec}/openjdk.jdk/Contents/Home"

    puts "java_home:", java_home
    # Remove Windows files
    rm_f Dir["bin/*.bat"]
    rm_f Dir["bin/*.exe"]

    # Install everything else into package directory
    libexec.install "bin", "config", "lib"

    # Set up Elasticsearch for local development:
    inreplace "#{libexec}/config/elasticsearch.yml" do |s|
      # 1. Give the cluster a unique name
      s.gsub!(/#\s*cluster\.name: .*/, "cluster.name: #{cluster_name}")
      s.gsub!(/#\s*network\.host: .*/, "network.host: 127.0.0.1")
      s.gsub!(/#\s*http\.port: .*/, "http.port: 9201")

      # 2. Configure paths
      s.sub!(%r{#\s*path\.data: /path/to.+$}, "path.data: #{var}/lib/#{name}/")
      s.sub!(%r{#\s*path\.logs: /path/to.+$}, "path.logs: #{var}/log/#{name}/")

    end

    config_file = "#{libexec}/config/elasticsearch.yml"
    open(config_file, "a") { |f|
        f.puts "index.number_of_shards: 1\n"
        f.puts "index.number_of_replicas: 0\n"
        f.puts "index.store.throttle.type: none\n"
        f.puts "node.local: true\n"
        f.puts "script.inline: on\n"
        f.puts "script.indexed: on\n"
    }

    # Move config files into etc
    (etc/"#{name}").install Dir[libexec/"config/*"]
    (libexec/"config").rmtree

    inreplace libexec/"bin/plugin",
              "CDPATH=\"\"",
              "JAVA_HOME=\"#{java_home}\"\nCDPATH=\"\""

    inreplace libexec/"bin/elasticsearch",
              "CDPATH=\"\"",
              "JAVA_HOME=\"#{java_home}\"\nCDPATH=\"\""
  end

  def post_install
    # Make sure runtime directories exist
    (var/"lib/#{name}").mkpath
    (var/"log/#{name}").mkpath
    ln_s etc/"#{name}", libexec/"config" unless (libexec/"config").exist?
    (var/"#{name}/plugins").mkpath
    ln_s var/"#{name}/plugins", libexec/"plugins" unless (libexec/"plugins").exist?
  end

  def caveats
    <<~EOS
      Data:    #{var}/lib/#{name}/
      Logs:    #{var}/log/#{name}/#{cluster_name}.log
      Plugins: #{var}/#{name}/plugins/
      Config:  #{etc}/#{name}/
    EOS
  end

  plist_options :manual => "vsh-elasticsearch1"

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
