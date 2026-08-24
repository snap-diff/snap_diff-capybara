# frozen_string_literal: true

require "fileutils"
require "json"

require "snap_diff/comparison"
require "snap_diff/region"

module SnapDiff
  # The message a user reads when a page would not hold still.
  #
  # It used to be a bare list of attempt paths (#271). That made diagnosis a
  # matter of opening N PNGs and eyeballing them, and faced with that versus
  # `sleep 2`, sleep wins -- so the suite got SLOWER as a consequence of the
  # diagnosis being hard. The information needed was already here and thrown
  # away: every consecutive pair of attempts is compared, and that comparison
  # knows the region that changed.
  #
  # So name it, and hand over the escape hatch that removes the need to sleep.
  class AttemptsReporter
    # One place on the page that changed between attempts, and how many of
    # the attempt pairs it showed up in. `pairs == total` means it changed
    # EVERY time -- an animation, and `skip_area` is the fix. Fewer means the
    # page was still rendering there, and masking would hide a real change.
    Area = Struct.new(:region, :pairs)

    def initialize(snapshot, comparison_options, stability_options = {})
      @snapshot = snapshot
      @comparison_options = comparison_options
      @wait = stability_options[:wait]
    end

    def generate
      # Sorted: `attempt_%02i` sorts lexically in capture order, and the
      # reader wants oldest-first regardless of what the glob hands back.
      attempts_screenshot_paths = @snapshot.find_attempts_paths.sort

      areas, dimensions = annotate_attempts(attempts_screenshot_paths)

      [
        "Could not get stable screenshot for '#{@snapshot.full_name}' within #{@wait}s " \
          "(#{attempts_screenshot_paths.size} attempts).",
        *diagnosis_lines(areas, dimensions),
        *attempts_screenshot_paths
      ].join("\n")
    end

    def build_comparison_for(attempt_path, previous_attempt_path)
      Comparison.new(attempt_path, previous_attempt_path, @comparison_options)
    end

    private

    # Annotates each attempt with its diff against the next one -- and keeps
    # the regions, which is the whole point of #271.
    #
    # @return [Array(Array<Area>, Array(Integer, Integer))] the clustered
    #   changed areas and the [width, height] of the attempts.
    def annotate_attempts(attempts_screenshot_paths)
      regions = []
      dimensions = nil
      previous_file = nil

      attempts_screenshot_paths.reverse_each do |file_name|
        if previous_file && File.exist?(previous_file)
          attempts_comparison = build_comparison_for(file_name, previous_file)

          if attempts_comparison.different?
            FileUtils.mv(attempts_comparison.reporter.annotated_base_image_path, previous_file, force: true)
            region = attempts_comparison.difference.region
            regions << region if region
            dimensions ||= dimensions_of(attempts_comparison)
          else
            warn "[capybara-screenshot-diff] Some attempts was stable, but mistakenly marked as not: " \
                   "#{previous_file} and #{file_name} are equal"
          end

          FileUtils.rm(attempts_comparison.reporter.annotated_image_path, force: true)
        end

        previous_file = file_name
      end

      # Worst offender first: the area that changed in the most pairs is the
      # one to act on, and a stable order keeps the message diffable.
      areas = cluster(regions).sort_by { |area| [-area.pairs, -area.region.size] }

      [areas, dimensions]
    end

    def dimensions_of(comparison)
      images = comparison.difference.comparison
      comparison.driver.dimension(images.base_image) if images&.base_image
    end

    # Groups the per-pair regions into the places on the page they occupy: a
    # region that overlaps one we have already seen is the same place, moved
    # or resized, so the place grows to cover both.
    #
    # ponytail: first-overlap wins, so a chain of regions that each overlap
    # the next merges into one area. That is the right answer for the case
    # this message exists for (something animating in one spot) and only ever
    # UNDER-counts areas, which cannot turn churn into a masking suggestion.
    def cluster(regions)
      regions.each_with_object([]) do |region, areas|
        existing = areas.find { |area| area.region.intersect?(region) }
        if existing
          existing.region = union(existing.region, region)
          existing.pairs += 1
        else
          areas << Area.new(region, 1)
        end
      end
    end

    def union(one, other)
      Region.from_edge_coordinates(
        [one.left, other.left].min,
        [one.top, other.top].min,
        [one.right, other.right].max,
        [one.bottom, other.bottom].max
      )
    end

    def diagnosis_lines(areas, dimensions)
      return [] if areas.empty? || dimensions.nil?

      total_pairs = areas.sum(&:pairs)
      # An area that changed in EVERY pair is animating. One that did not is
      # the page still rendering -- masking it would hide a real change.
      animating, settling = areas.partition { |area| area.pairs == total_pairs }

      [
        "  The page kept changing in #{count(areas.size, "area")}, over #{count(total_pairs, "attempt pair")}:",
        *areas.map { |area| "    #{area_line(area, total_pairs, dimensions)}" },
        *animating_lines(animating),
        *settling_lines(settling, animating)
      ]
    end

    def area_line(area, total_pairs, dimensions)
      width, height = dimensions
      share = area.region.size.to_f / (width * height)

      "#{area.region.to_edge_coordinates.to_json} (left,top,right,bottom edges) " \
        "-- #{Reporters::Default.percent(share)} of the #{width}x#{height} image, " \
        "changed in #{area.pairs} of #{total_pairs} pairs"
    end

    # The escape hatch. Every coordinate here came off the comparison that
    # just ran -- never a placeholder, and never a knob nothing reads.
    def animating_lines(animating)
      return [] if animating.empty?

      skip_area = animating.map { |area| area.region.to_edge_coordinates }
      skip_area = skip_area.first if skip_area.size == 1

      [
        "  Always the same area, in every pair: that is an animation, clock, carousel or live counter.",
        "  Exclude it and the page is stable without waiting:",
        "    assert_matches_screenshot #{@snapshot.full_name.to_s.inspect}, skip_area: #{skip_area.to_json}"
      ]
    end

    def settling_lines(settling, animating)
      return [] if settling.empty?

      subject = animating.empty? ? "D" : "The other #{count(settling.size, "area")}: d"

      [
        "  #{subject}ifferent areas at different times -- the page is still rendering, not animating in one place.",
        "  skip_area masks a fixed area and will not help here: settle the page first (a readiness",
        "  block on the assertion -- see docs/configuration.md) or raise wait:."
      ]
    end

    def count(number, noun)
      "#{number} #{noun}#{"s" unless number == 1}"
    end
  end
end
