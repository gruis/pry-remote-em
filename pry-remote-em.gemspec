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

  s.add_dependency 'eventmachine'
  s.add_dependency 'msgpack'
  s.add_dependency 'pry', '~> 0.11'
  s.add_dependency 'ruby-termios', '~> 1.0'
  s.add_dependency 'highline', '~> 2.0'
end
