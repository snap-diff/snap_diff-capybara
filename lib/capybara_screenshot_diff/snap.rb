# frozen_string_literal: true

module CapybaraScreenshotDiff
  class Snap
    attr_reader :full_name, :format, :path, :base_path, :manager, :attempt_path, :prev_attempt_path, :attempts_count

    def initialize(full_name, format, manager: SnapManager.instance)
      @full_name = full_name
      @format = format
      @path = manager.abs_path_for(Pathname.new(@full_name).sub_ext(".#{@format}"))
      @base_path = @path.sub_ext(".base.#{@format}")
      @manager = manager
      @attempts_count = 0
    end

    def delete!
      path.delete if path.exist?
      base_path.delete if base_path.exist?
      cleanup_attempts
    end

    def checkout_base_screenshot
      @manager.checkout_file(path, base_path)
    end

    def path_for(version = :actual)
      case version
      when :base
        base_path
      else
        path
      end
    end

    def next_attempt_path!
      @prev_attempt_path = @attempt_path
      @attempt_path = path.sub_ext(sprintf(".attempt_%02i.#{format}", @attempts_count))
    ensure
      @attempts_count += 1
    end

    def commit_last_attempt
      @manager.move(attempt_path, path)
    end

    def cleanup_attempts
      @manager.cleanup_attempts!(self)
      @attempts_count = 0
    end

    def find_attempts_paths
      Dir[@manager.abs_path_for "**/#{full_name}.attempt_*.#{format}"]
    end
  end
end
