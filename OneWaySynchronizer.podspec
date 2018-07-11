Pod::Spec.new do |s|

  s.name         = "OneWaySynchronizer"
  s.version      = "1.1.0"
  s.summary      = "OneWaySynchronizer - the simplest way to sync data from remote host into local storage."

  s.homepage         = "https://github.com/ladeiko/OneWaySynchronizer"
  s.license          = 'MIT'
  s.authors           = { "Siarhei Ladzeika" => "sergey.ladeiko@gmail.com" }
  s.source           = { :git => "https://github.com/ladeiko/OneWaySynchronizer.git", :tag => s.version.to_s }
  s.ios.deployment_target = '9.0'
  s.requires_arc = true

  s.source_files =  "Source/*.swift"

end
