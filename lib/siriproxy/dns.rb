require 'rubydns'

class SiriProxy::Dns
  attr_accessor :interfaces, :upstream, :thread

  def initialize
    @interfaces = [
      [:tcp, "0.0.0.0", 53],
      [:udp, "0.0.0.0", 53]
    ]
  
    servers = []

    $APP_CONFIG.upstream_dns.each { |dns_addr|
      servers << [:udp, dns_addr, 53]
      servers << [:tcp, dns_addr, 53]
    }

    @upstream = RubyDNS::Resolver.new(servers)
  end

  def start(log_level=Logger::WARN)
    @thread = Thread.new {
      begin
        self.run(log_level)
      rescue RuntimeError => e
        if e.message.match /^no acceptor/
          puts "[Error - Server] You must be root to run the DNS server, DNS server is disabled"
        else
          puts "[Error - Server] DNS Error: #{e.message}"
          puts "[Error - Server] DNS Server has crashed. Terminating SiriProxy"
          exit 1
        end
      rescue Exception => e
        puts "[Error - Server] DNS Error: #{e.message}"
        puts "[Error - Server] DNS Server has crashed. Terminating SiriProxy"
        exit 1
      end
    }
  end

  def stop
    Thread.kill(@thread)
  end

  def run(log_level=Logger::WARN,server_ip=$APP_CONFIG.server_ip)
    if server_ip
      upstream = @upstream
        
      # Start the RubyDNS server
      RubyDNS::run_server(:listen => @interfaces) do
        @logger.level = log_level

        match(/guzzoni.apple.com/, Resolv::DNS::Resource::IN::A) do |_host, transaction|
          transaction.respond!(server_ip)
        end

        # Default DNS handler
        otherwise do |transaction|
          transaction.passthrough!(upstream)
        end
      end

      puts "[Info - Server] DNS Server started, tainting 'guzzoni.apple.com' with #{server_ip}"
    end
  end
end
