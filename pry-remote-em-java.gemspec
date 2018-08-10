require File.expand_path('../lib/pry-remote-em/version', __FILE__)

Gem::Specification.new do |s|
  s.name          = 'pry-remote-em'
  s.version       = PryRemoteEm::VERSION
  s.summary       = 'Connect to Pry remotely using EventMachine'
  s.description   = 'Connect to Pry remotely using EventMachine with tab-completion, paging, user auth and SSL'
  s.homepage      = 'https://github.com/gruis/pry-remote-em'
  s.email         = 'pry-remote-em@simulacre.org'
  s.authors       = ['Caleb Crane', 'Xanders']
  s.files         = Dir['lib/**/*.rb', 'bin/*', '*.md']
  s.require_paths = ['lib']
  s.executables   = ['pry-remote-em', 'pry-remote-em-broker']
  s.license       = 'Nonstandard'

  s.add_runtime_dependency 'eventmachine', '~> 1'
  s.add_runtime_dependency 'msgpack', '~> 1'
  s.add_runtime_dependency 'pry', '~> 0.11'
  s.add_runtime_dependency 'highline', '~> 2.0'

  s.platform = 'java'
end
