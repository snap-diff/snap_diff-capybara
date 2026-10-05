# frozen_string_literal: true

module SnapDiff
  module Ai
    # Offline default: CLIP embeddings via the +informers+ gem (ONNX,
    # ~90 MB quantized, ~40 ms/image, no network). Returns only
    # :similarity; verdicts come from Ai.verdict.
    class Clip
      def name = "clip"

      def initialize(model: "Xenova/clip-vit-base-patch32", pipeline: nil)
        require "informers" unless pipeline
        @model = model
        @pipeline = pipeline
        @mutex = Mutex.new # ONNX session thread safety is not guaranteed
      end

      def call(name:, base:, current:, meta: {})
        {similarity: cosine(base, current)&.round(4)}
      end

      # Downloads and loads the model NOW. Run at suite setup (or a CI
      # cache step) so the first diff is analyzed offline: without a
      # prefetched model, the first diff pulls ~90 MB over the network.
      def prefetch!
        pipeline
      end

      private

      def pipeline
        # Lazy: the one-time model download lands on the first diff,
        # not at reporter registration. Memoized per model.
        @pipeline ||= Informers.pipeline("image-feature-extraction", @model, quantized: true)
      end

      def cosine(path_a, path_b)
        return unless path_a && path_b && File.exist?(path_a) && File.exist?(path_b)

        a, b = @mutex.synchronize { [pipeline.call(path_a).first, pipeline.call(path_b).first] }
        norm = Math.sqrt(a.sum { |x| x * x }) * Math.sqrt(b.sum { |x| x * x })
        a.zip(b).sum { |x, y| x * y } / norm if norm.positive?
      end
    end

    register(:clip) { Clip.new }
  end
end
