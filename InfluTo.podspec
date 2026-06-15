Pod::Spec.new do |s|
  s.name             = 'InfluTo'
  s.version          = '1.0.0'
  s.summary          = 'InfluTo influencer attribution + store-direct purchase validation.'
  s.homepage         = 'https://influ.to'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'InfluTo' => 'support@influ.to' }
  s.source           = { :git => 'https://github.com/influto/influto-ios.git', :tag => s.version.to_s }
  s.swift_version    = '5.9'
  s.ios.deployment_target = '16.0'
  s.osx.deployment_target = '13.0'
  s.source_files     = 'Sources/InfluTo/**/*.swift'
  s.resource_bundles = { 'InfluTo' => ['Sources/InfluTo/PrivacyInfo.xcprivacy'] }
  s.frameworks       = 'Foundation', 'StoreKit'
end
