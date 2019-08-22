# Idea stolen from clearance gem (https://github.com/thoughtbot/clearance)
module RediLimit
  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end

  class Configuration
    attr_accessor :redis_host

    def initialize
      @redis_host = :localhost
    end
  end
end