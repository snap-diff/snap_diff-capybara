# frozen_string_literal: true

require "capybara/screenshot/diff/image_compare"

module CapybaraScreenshotDiff
  class AttemptsReporter
    def initialize(snapshot, comparison_options, stability_options = {})
      @snapshot = snapshot
      @comparison_options = comparison_options
      @wait = stability_options[:wait]
    end

    def generate
      attempts_screenshot_paths = @snapshot.find_attempts_paths

      annotate_attempts(attempts_screenshot_paths)

      "Could not get stable screenshot within #{@wait}s:\n#{attempts_screenshot_paths.join("\n")}"
    end

    def build_comparison_for(attempt_path, previous_attempt_path)
      Capybara::Screenshot::Diff::ImageCompare.new(attempt_path, previous_attempt_path, @comparison_options)
    end

    private

    def annotate_attempts(attempts_screenshot_paths)
      previous_file = nil
      attempts_screenshot_paths.reverse_each do |file_name|
        if previous_file && File.exist?(previous_file)
          attempts_comparison = build_comparison_for(file_name, previous_file)

          if attempts_comparison.different?
            FileUtils.mv(attempts_comparison.reporter.annotated_base_image_path, previous_file, force: true)
          else
            warn "[capybara-screenshot-diff] Some attempts was stable, but mistakenly marked as not: " \
                   "#{previous_file} and #{file_name} are equal"
          end

          FileUtils.rm(attempts_comparison.reporter.annotated_image_path, force: true)
        end

        previous_file = file_name
      end

      previous_file
    end
  end
end
