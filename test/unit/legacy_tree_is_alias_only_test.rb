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

  # THE ALLOWLIST -- and as of ADR-008 step 7b it is EMPTY: not one file in
  # the v1 trees holds logic any more. config_legacy.rb was the last entry;
  # step 7b moved its derived config (.active? precedence, .screenshot_area
  # path assembly, .default_options incl. the vips tolerance literal) into
  # SnapDiff::Config, and the Config::MAPPING accessor generator into
  # snap_diff/config.rb alongside it, leaving only one-line forwarders.
  #
  # Keep it empty. Adding an entry back is a decision to keep behaviour on
  # the v1 side of the 3.0 deletion, so it needs a written reason here AND
  # an ADR-008 update -- never just to turn a red build green.
  #
  # (Diff::AVAILABLE_DRIVERS still lives in config_legacy.rb, but as a bare
  # constant assignment it is alias-shaped and needs no exemption. It stays
  # there on purpose -- see #227: test_helper reads it at boot and
  # image_compare_test stubs it as the published no-drivers hook.)
  ALLOWED_WITH_CODE = {}.freeze

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

  # The pinned method inventory that used to narrow config_legacy.rb's
  # allowlist entry is gone with the entry itself (ADR-008 step 7b): with
  # nothing allowlisted, the general rule above already checks every `def`
  # in the tree, config_legacy.rb's included.
  test "the allowlist is empty, so nothing is exempt from the general rule" do
    assert_empty ALLOWED_WITH_CODE,
      "an exemption came back -- see the comment on ALLOWED_WITH_CODE before keeping it"
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
