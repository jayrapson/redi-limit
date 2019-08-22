require 'redis'
require 'openssl'
require 'contracts'
require_relative '../configuration'

module RediLimit
  class Base
    include Contracts::Core
    include Contracts::Builtin

    LIMIT_HTTP_CODE = 429

    attr_reader :app, :script_id

    def initialize(app)
      @app = app
      @script_id = load_script!
    end

    def call(env)
      return app.call(env) if skip?(env)

      begin
        limit(env)
      rescue Exception => e
        # Potentially explicitly send to sentry/airbrake/honeybadger etc. at this point as we're high in 
        # the pipeline and depending on the integration it may not be captured.
        logger.error(e)
        raise e
      end
    end

    # Check whether the request should be limited, and if so return the appropriate rate limit message
    # In the default case we return a normal response and continue down the pipeline
    def limit(env)
      app.call(env)
    end

    # Test whether this rule should be checked, or just skipped over. This is where you begin to implement 
    # more complex rules (i.e. only limiting specific authenticated endpoints)
    def skip?(env)
      false
    end

    # Execute the remote script and return the results
    def run_script(*args)
      begin
        revoke_in = redis.evalsha(script_id, argv: args)
      rescue Redis::CommandError => e
        if e.message.match(/NOSCRIPT/)
          # In this case, the script isn't available due to a redis restart or failure, we can add 
          # reload the script and try again. See https://redis.io/commands/eval
          # If this doesn't resolve the issue, just let the exception bubble up
          load_script!
          redis.evalsha(script_id, argv: args)
        else
          raise e
        end
      end
    end

    protected

    # Build a rate limited response
    def restrict(message, identifier, headers = {})
      logger.warn("#{self.class.name} limited #{identifier} with '#{message}'")
      [LIMIT_HTTP_CODE, headers, [message]]
    end

    # Specify a custom Lua script to be loaded into the redis cluster
    # I'm on the fence about using NotImplementedError to create abstract methods, though this is often 
    # used for this purpose, the intention behind the error is meant to be quite different. The other 
    # popular options of not defining the method on the base class at all, or raising a generic error, 
    # don't sit well with me either.
    def script_name
      raise NotImplementedError
    end

    # Configure Redis client for easy access, in a production environment this would be configured with 
    # SSL and the relevant secrets.
    def redis
      @redis ||= Redis.new(host: RediLimit.configuration.redis_host)
    end

    def hash(v)
      OpenSSL::Digest::SHA1.hexdigest(v)
    end

    def logger
      @logger ||= Logger.new(STDOUT)
    end

    private

    # Preload the relevant Lua script into Redis and ensure we have the correct SHA to reference
    def load_script!
      # load the relative path to the script
      source = File.read(script_path)
      redis.script(:load, source)

      # Return the SHA of the script to allow calls to reference the script later on
      hash(source)
    end

    # The relative path to the Lua script
    def script_path
      File.join(__dir__, 'scripts', "#{script_name}.lua")
    end
  end
end