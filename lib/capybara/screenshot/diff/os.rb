module Capybara
  module Screenshot
    module Os
      ON_WINDOWS = RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
      ON_MAC = RbConfig::CONFIG['host_os'] =~ /darwin/
      ON_LINUX = RbConfig::CONFIG['host_os'] =~ /linux/

      def os_name
        return 'windows' if ON_WINDOWS
        return 'macos' if ON_MAC
        return 'linux' if ON_LINUX
        'unknown'
      end
    end
  end
end
