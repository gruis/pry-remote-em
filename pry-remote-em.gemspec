require File.expand_path('../lib/pry-remote-em/version', __FILE__)

Gem::Specification.new do |s|
  s.name          = 'pry-remote-em'
  s.version       = PryRemoteEm::VERSION
  s.summary       = 'Connect to Pry remotely using EventMachine'
  s.description   = 'Connect to Pry remotely using EventMachine with tab-completion, paging, user auth and SSL'
  s.homepage      = 'http://github.com/simulacre/pry-remote-em'
  s.email         = 'pry-remote-em@simulacre.org'
  s.authors       = ['Caleb Crane']
  s.files         = Dir["lib/**/*.rb", "bin/*", "*.md"]
  s.require_paths = ["lib"]
  s.executables   = ['pry-remote-em']

  s.add_dependency 'eventmachine'
  s.add_dependency 'pry', '~> 0.9.6'
  s.add_dependency 'rb-readline'
  s.add_dependency 'highline'
end
