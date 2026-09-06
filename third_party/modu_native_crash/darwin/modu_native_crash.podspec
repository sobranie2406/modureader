Pod::Spec.new do |s|
  s.name = 'modu_native_crash'
  s.version = '0.1.0'
  s.summary = 'Local-only, allowlisted MetricKit crash summaries.'
  s.description = s.summary
  s.homepage = 'https://github.com/sobranie2406/modureader'
  s.license = { :type => 'GPL-3.0' }
  s.author = { 'Modu contributors' => 'https://github.com/sobranie2406/modureader' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '14.0'
  s.osx.deployment_target = '12.0'
  s.frameworks = 'MetricKit'
  s.swift_version = '5.0'
end
