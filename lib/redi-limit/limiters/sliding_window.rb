require_relative 'base'

# Contracts are intentionally implemented on initialize to simplify initial setup and reduce
# the chance of user error, and not included on the 'check' method due to simplicity and 
# performance concerns.

module RediLimit
  class SlidingWindow < RediLimit::Base
    attr_reader :window, :rate, :header_group

    Contract Any, Pos, Pos, Maybe[String] => Any
    def initialize(app, rate, window, header_group = 'HTTP_AUTHORIZATION')
      @rate = rate
      @window = window.to_i
      @header_group = header_group
      super(app)
    end

    # Only continue if the relevant header is present
    def skip?(env)
      !env.key?(header_group)
    end

    def limit(env)
      # Hash the identifier in case the header contains sensitive information
      identifier = hash(env[header_group])

      # Check whether the request should be blocked. Returns either the number of seconds until
      # the limit is revoked, or nil if there is no limit.
      revoke_in = run_script(identifier, window, rate, Time.now.to_i)
      
      if revoke_in != nil && revoke_in > 0
        # They're in a restricted state, return them a relevant message
        restrict("Rate limit exceeded, try again in #{revoke_in} seconds", identifier)
      else
        # Continue down through the pipeline as normal
        super
      end
    end

    def script_name
      'sliding_window'
    end
  end
end