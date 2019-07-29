require "redis"

abstract class EngineDriver; end

class EngineDriver::RedisClient < ::Redis
  REDIS_URL  = ENV["REDIS_URL"]?
  REDIS_HOST = ENV["REDIS_HOST"]? || "localhost"
  REDIS_PORT = (ENV["REDIS_PORT"]? || 6379).to_i

  def initialize(host = REDIS_HOST, port = REDIS_PORT, url = REDIS_URL)
    if url
      super(url: url)
    else
      super(host: host, port: port)
    end
  end

  class Pool < ::Redis::PooledClient
    @@instance : ::Redis::PooledClient?

    def self.instance : ::Redis::PooledClient
      @@instance ||= self.new
    end

    def initialize(host = REDIS_HOST, port = REDIS_PORT, url = REDIS_URL)
      if url
        super(url: url)
      else
        super(host: host, port: port)
      end
    end
  end
end
