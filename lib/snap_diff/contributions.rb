# frozen_string_literal: true

# Contribution points: how OPTIONAL modules (AI triage today, anything
# else tomorrow) feed the reports and the failure decision without the
# reporters or the assertion knowing those modules exist.
#
# The contract follows the two proven shapes in the ecosystem:
# Minitest's CompositeReporter (plugins append themselves to a
# core-owned list; core calls a uniform interface and never names a
# plugin) and SimpleCov's formatter pipeline (consumers receive a plain
# data payload, never a plugin's class). A contributor is any object
# responding to #annotate(name) -> {source:, text:, data:} or nil;
# reports render whatever comes back.
#
# Failure suppression is deliberately a SINGLE slot (it was
# SnapDiff::AI.gate before): two gates with different accept-lists
# would silently suppress each other's real bugs, so registration
# replaces the previous gate rather than stacking.
module SnapDiff
  module Contributions
    @providers = []
    @suppression = nil
    @mutex = Mutex.new

    class << self
      # Register a report contributor. The provider must respond to
      # #annotate(name), returning {source:, text:, data: (optional)}
      # or nil. Registering the same object twice is a no-op -- identity,
      # not ==: two distinct providers that happen to compare equal
      # (e.g. Structs with equal fields) must BOTH contribute.
      def register(provider)
        @mutex.synchronize { @providers << provider unless @providers.any? { |p| p.equal?(provider) } }
      end

      # All contributions for one screenshot, in registration order.
      # Empty when nothing is registered -- the no-AI default.
      def annotations_for(name)
        @mutex.synchronize { @providers.dup }.filter_map { |provider| provider.annotate(name) }
      end

      # The one failure gate: #suppress(name, difference) ->
      # {source:, text:} (failure waived) or nil (failure stands).
      # nil clears the slot (test teardown, reconfiguration).
      def register_suppression(provider)
        @mutex.synchronize { @suppression = provider }
      end

      # Cheap probe so callers can skip building `difference` entirely
      # when no gate is registered.
      def any_suppressor?
        @mutex.synchronize { !@suppression.nil? }
      end

      # Ask the current suppressor to evaluate a screenshot difference.
      # Return its {source:, text:} waiver, or nil when no gate waives the failure.
      def suppression_for(name, difference)
        @mutex.synchronize { @suppression }&.suppress(name, difference)
      end
    end
  end
end
