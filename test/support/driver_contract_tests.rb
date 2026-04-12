# frozen_string_literal: true

# Shared contract tests for all image processing drivers.
# Include in any driver test class that uses DSLStub (provides make_comparison).
module DriverContractTests
  extend ActiveSupport::Concern

  included do
    test "[contract] quick_equal? returns true for identical images" do
      comp = make_comparison(:a, :a)
      assert comp.quick_equal?
    end

    test "[contract] different? returns false for identical images" do
      comp = make_comparison(:a, :a)
      assert_not comp.different?
    end

    test "[contract] different? returns true for different images" do
      comp = make_comparison(:a, :c)
      assert comp.different?
    end

    test "[contract] different? generates annotated images for different images" do
      comp = make_comparison(:a, :c)
      assert comp.different?

      assert File.exist?(comp.reporter.annotated_base_image_path)
      assert File.exist?(comp.reporter.annotated_image_path)
    end

    test "[contract] different? does not create annotated images for identical images" do
      comp = make_comparison(:c, :c)
      assert_not comp.different?

      assert_not File.exist?(comp.reporter.annotated_base_image_path)
      assert_not File.exist?(comp.reporter.annotated_image_path)
    end
  end
end
