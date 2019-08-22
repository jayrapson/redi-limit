$LOAD_PATH.unshift(File.expand_path('../lib', __FILE__))
require 'version'

Gem::Specification.new do |s|
  s.name          = "redi-limit"
  s.version       = RediLimit::VERSION
  s.authors       = ['Jay Rapson']
  s.email         = ['jay.rapson@me.com']
  s.summary       = 'Rack based middleware rate limiting using lua scripts in redis'
  s.homepage      = 'https://github.com/jayrapson/redi-limit'

  s.files  = Dir['lib/**/*.{rb,lua}']

  s.require_paths = ['lib']

  s.add_development_dependency "rake", "~> 10.0"
  s.add_development_dependency "rspec", "~> 3.5"

  s.add_dependency 'contracts', '~> 0.16.0'
  s.add_dependency 'rack', '~> 2.0'
  s.add_dependency 'redis', '~> 4.0'

  s.licenses = ['MIT']
end