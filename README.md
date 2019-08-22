# RediLimit
Middleware rate limiting using preloaded lua scripts in redis for rails

## Disclaimer
This project was created as a quick time restricted coding challenge, if you stumble across this project, it is not ready for production use. Please don't attempt to use it in production. **Please don't.**

## Getting Started
1. Add to your Gemfile and run the `bundle` command to install

```sh
gem 'redi-limit', git: 'git@github.com:jayrapson/redi-limit.git'
```

2. Configure your connection details in `config/initializers/redi-limit.rb`

```ruby
RediLimit.configure do |config|
	config.redis_host = 'localhost'
end
```

3. Add the relevant rate limiter to middleware:

```ruby
config.middleware.insert_before(0, RediLimit::SlidingWindow, 100, 1.hour, 'HTTP_AUTHORIZATION')
```

You can also stack multiple of the same rate limiters to your middleware to achieve the desired effect:

```ruby
# Limit authorised requests to 100 per hour
config.middleware.insert_before(0, RediLimit::SlidingWindow, 100, 1.hour, 'HTTP_AUTHORIZATION')
# Limit requests to 500 per minute based on their IP address
config.middleware.insert_before(1, RediLimit::SlidingWindow, 500, 1.minute, 'REMOTE_ADDR')
```

## Development
After checking out the repo, run the `bundle` command to install the relevant dependencies

To run the test suite you must have access to a local redis, due to the use of embedded Lua scripts mocking/stubbing this dependency provides little value. Due to the low cyclomatic complexity of the Lua scripts being used, these tests make do with testing basic functionality by calling them directly. The ideal solution would be to implement tests on the internal logic of the scripts using [busted](https://github.com/Olivine-Labs/busted) whilst using a wrapper to allow interaction with the redis object. 

To run the included tests run:
```sh
rspec
```