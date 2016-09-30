#
# Be sure to run `pod lib lint GRCoreData.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'GRCoreData'
  s.version          = '1.0.0'
  s.summary          = 'Helpful code for working with Core Data'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
CoreDataStack with support for multiple contexts and some much-needed syntactic sugar.
                       DESC

  s.homepage         = 'https://github.com/jgrantr/GRCoreData'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Grant Robinson' => 'grant@zayda.com' }
  s.source           = { :git => 'https://github.com/jgrantr/GRCoreData.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '8.0'

  s.source_files = 'GRCoreData/Classes/**/*'
  
  # s.resource_bundles = {
  #   'GRCoreData' => ['GRCoreData/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  s.frameworks = 'Foundation', 'CoreData'
  s.dependency 'PromiseKit', '~> 3.5'
end
