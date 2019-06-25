require "http"
require "socket"
require "base64"
require "openssl"

class EngineDriver; end

# Based on https://github.com/net-ssh/net-ssh/blob/master/lib/net/ssh/proxy/http.rb
class EngineDriver::HTTPProxy
  # The hostname or IP address of the HTTP proxy.
  getter proxy_host : String

  # The port number of the proxy.
  getter proxy_port : Int32

  # The map of additional options that were given to the object at
  # initialization.
  getter tls : OpenSSL::SSL::Context::Client?

  # Create a new socket factory that tunnels via the given host and
  # port. The +options+ parameter is a hash of additional settings that
  # can be used to tweak this proxy connection. Specifically, the following
  # options are supported:
  #
  # * :user => the user name to use when authenticating to the proxy
  # * :password => the password to use when authenticating
  def initialize(host, port = 80, @auth : NamedTuple(username: String, password: String)? = nil)
    @proxy_host = host
    @proxy_port = port
  end

  # Return a new socket connected to the given host and port via the
  # proxy that was requested when the socket factory was instantiated.
  def open(host, port, tls = nil, **connection_options)
    dns_timeout = connection_options.fetch(:dns_timeout, nil)
    connect_timeout = connection_options.fetch(:connect_timeout, nil)
    read_timeout = connection_options.fetch(:read_timeout, nil)

    socket = TCPSocket.new @proxy_host, @proxy_port, dns_timeout, connect_timeout
    socket.read_timeout = read_timeout if read_timeout
    socket.sync = true

    socket << "CONNECT #{host}:#{port} HTTP/1.0\r\n"

    if auth = @auth
      credentials = Base64.strict_encode("#{auth[:username]}:#{auth[:password]}")
      credentials = credentials.gsub(/\s/, "")
      socket << "Proxy-Authorization: Basic #{credentials}\r\n"
    end

    socket << "\r\n"

    resp = parse_response(socket)

    if resp[:code]? == 200
      if tls
        tls_socket = OpenSSL::SSL::Socket::Client.new(socket, context: tls, sync_close: true, hostname: host)
        socket = tls_socket
      end

      return socket
    else
      socket.close
      raise IO::Error.new(resp.inspect)
    end
  end

  private def parse_response(socket)
    resp = {} of Symbol => Int32 | String | Hash(String, String)

    begin
      version, code, reason = socket.gets.as(String).chomp.split(/ /, 3)

      headers = {} of String => String

      while (line = socket.gets.as(String)) && (line.chomp != "")
        name, value = line.split(/:/, 2)
        headers[name.strip] = value.strip
      end

      resp[:version] = version
      resp[:code] = code.to_i
      resp[:reason] = reason
      resp[:headers] = headers
    rescue
    end

    return resp
  end
end

class EngineDriver::HTTPClient < ::HTTP::Client
  def set_proxy(proxy : HTTPProxy)
    socket = @socket
    return if socket && !socket.closed?

    begin
      @socket = proxy.open(@host, @port, @tls, **proxy_connection_options)
    rescue IO::Error
      @socket = nil
    end
  end

  def proxy_connection_options
    {
      dns_timeout: @dns_timeout,
      connect_timeout: @connect_timeout,
      read_timeout: @read_timeout
    }
  end

  def check_socket_valid
    socket = @socket
    @socket = nil if socket && socket.closed?
  end
end