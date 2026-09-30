Pod::Spec.new do |s|
  s.name             = 'chatterloop_call_native'
  s.version          = '0.1.0'
  s.summary          = 'Native call support for Chatterloop.'
  s.description      = 'The ringer, the ongoing-call state and picture-in-picture for Chatterloop calls.'
  s.homepage         = 'https://chatterloop.app'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Chatterloop' => 'dev@chatterloop.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
