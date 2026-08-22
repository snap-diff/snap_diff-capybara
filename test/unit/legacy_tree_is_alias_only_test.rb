# frozen_string_literal: true

require "test_helper"

# ADR-008 step 7: the mechanical gate that keeps 3.0 a `git rm`.
#
# lib/capybara/ and lib/capybara_screenshot_diff/ are the v1 compatibility
# surface. Every unit of behaviour has moved to lib/snap_diff/, so what is
# left must be nothing but requires, namespace reopening, constant aliases
# and one-line forwarders. If that stays true, dropping v1 support in 3.0 is
# a deletion; the moment real logic lands back in these trees it becomes a
# refactor. This test fails the second that happens, naming the file.
class LegacyTreeIsAliasOnlyTest < ActiveSupport::TestCase
  LIB = Pathname.new(__dir__).join("../../lib").expand_path

  LEGACY_FILES = (
    Dir[LIB.join("capybara*.rb")] +
    Dir[LIB.join("capybara/**/*.rb")] +
    Dir[LIB.join("capybara_screenshot_diff/**/*.rb")]
  ).map { |path| Pathname.new(path) }.sort.freeze

  # THE ALLOWLIST. Every entry is a file that legitimately still holds code,
  # with the reason. This list is the honest state of the tree -- keep it in
  # sync with ADR-008, and never add to it to make a red build green without
  # first asking whether the code belongs in lib/snap_diff/ instead.
  ALLOWED_WITH_CODE = {
    # ADR-008 step 1 moved config STORAGE to SnapDiff::Config and generates
    # the old accessor names here from Config::MAPPING (delegation, but via
    # define_method). It also still holds DERIVED config logic that never
    # moved: .active? precedence, .screenshot_area path assembly and
    # .default_options (which carries one literal default, the vips
    # tolerance 0.001). Narrowed below by pinning the method inventory, so
    # new logic here still reds. AVAILABLE_DRIVERS also lives here on
    # purpose (see #227: test_helper reads it at boot, image_compare_test
    # stubs it) -- the gate does not push it out.
    "capybara/screenshot/diff/config_legacy.rb" => "generates delegating accessors from Config::MAPPING; retains derived config logic (ADR-008 step 1)"
  }.freeze

  # Shapes that are pure compatibility plumbing rather than behaviour.
  ALIAS_SHAPES = /\A(
    require(_relative)?\s |
    autoload\s |
    (module|class)\s |
    end\z |
    private\z |
    (extend|include)\s |
    [A-Z]\w*\s*=\s |          # constant alias: Foo = SnapDiff::Foo
    def_delegators?\s
  )/x

  test "every legacy file is aliases and forwarders only" do
    refute_empty LEGACY_FILES, "legacy tree glob matched nothing -- the gate would pass vacuously"

    offenders = LEGACY_FILES.reject { |file| allowed?(file) }.flat_map { |file| offences(file) }

    assert_empty offenders, <<~MSG
      Real logic found in the v1 compatibility trees. Move it to lib/snap_diff/
      (or, if it genuinely must stay, add the file to ALLOWED_WITH_CODE with a
      written reason and update ADR-008):

      #{offenders.join("\n")}
    MSG
  end

  test "config_legacy.rb keeps exactly its known set of methods" do
    source = LIB.join("capybara/screenshot/diff/config_legacy.rb").read
    defined_methods = source.scan(/^\s*def\s+(self\.)?([a-z_]\w*[?!]?)/).map { |receiver, name| "#{receiver}#{name}" }

    assert_equal(
      ["active?", "screenshot_area", "screenshot_area_abs", "self.compare", "self.configure", "self.default_options"],
      defined_methods.sort,
      "config_legacy.rb is allowlisted for the logic it already had, not for new logic -- move new methods to lib/snap_diff/"
    )
  end

  private

  def allowed?(file)
    ALLOWED_WITH_CODE.key?(file.relative_path_from(LIB).to_s)
  end

  # Walks the file's significant lines. A `def` is only acceptable when its
  # whole body is a single line delegating into SnapDiff; anything else must
  # match ALIAS_SHAPES.
  def offences(file)
    rel = file.relative_path_from(LIB)
    lines = significant_lines(file)
    found = []
    index = 0

    while index < lines.length
      line = lines[index]

      if line.start_with?("def ")
        body, terminator = lines[index + 1], lines[index + 2]
        unless body.to_s.include?("SnapDiff") && terminator == "end"
          found << "#{rel}: `#{line}` is not a one-line forwarder into SnapDiff"
        end
        index += 3
      else
        found << "#{rel}: unexpected line `#{line}`" unless ALIAS_SHAPES.match?(line)
        index += 1
      end
    end

    found
  end

  # Strips comments and blanks, and folds trailing-comma continuations back
  # into one logical line (multi-line def_delegators lists, hash literals).
  def significant_lines(file)
    file.read.lines.map(&:strip)
      .reject { |line| line.empty? || line.start_with?("#") }
      .each_with_object([]) do |line, folded|
        if folded.last&.end_with?(",")
          folded[-1] = "#{folded.last} #{line}"
        else
          folded << line
        end
      end
  end
end
