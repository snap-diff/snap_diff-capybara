module Capybara
  module Screenshot
    module Os
      ON_WINDOWS = RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/

      def os_name
        case RbConfig::CONFIG['host_os']
        when /darwin/
          'macos'
        when /mswin|mingw|cygwin/
          'windows'
        when /linux/
          'linux'
        else
          'unknown'
        end
      end

      private def macos?
        os_name == 'macos'
      end
    end
  end
end
