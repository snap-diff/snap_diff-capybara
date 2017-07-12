require 'chunky_png'

module Capybara
  module Screenshot
    module Diff
      class ImageCompare
        include ChunkyPNG::Color

        attr_reader :annotated_new_file_name, :annotated_old_file_name, :new_file_name

        def self.compare(*args)
          new(*args).different?
        end

        def self.annotated_old_file_name(new_file_name)
          "#{new_file_name.chomp('.png')}_0.png~"
        end

        def initialize(old_file_name, new_file_name, dimensions: nil, color_distance_limit: nil,
            area_size_limit: nil)
          @old_file_name = old_file_name
          @new_file_name = new_file_name
          @color_distance_limit = color_distance_limit
          @area_size_limit = area_size_limit
          @dimensions = dimensions
          @annotated_old_file_name = self.class.annotated_old_file_name(new_file_name)
          @annotated_new_file_name = "#{new_file_name.chomp('.png')}_1.png~"
          reset
        end

        def reset
          @max_color_distance = @color_distance_limit ? 0 : nil
          @left = @top = @right = @bottom = nil
        end

        # Compare the two image files and return `true` or `false` as quickly as possible.
        # Return falsish if the old file does not exist or the image dimensions do not match.
        def quick_equal?
          return nil unless old_file_exists?
          return true if new_file_size == old_file_size
          old_file, new_file = load_image_files(@old_file_name, @new_file_name)
          return true if old_file == new_file
          images = load_images(old_file, new_file)
          crop_images(images, @dimensions) if @dimensions

          old_img = images.first
          new_img = images.last

          return false if sizes_changed?(old_img, new_img)

          return true if old_img.pixels == new_img.pixels

          @left, @top, @right, @bottom = find_top(old_img, new_img)

          return true if @top.nil?

          false
        end

        # Compare the two images referenced by this object, and return `true` if they are different,
        # and `false` if they are the same.
        # Return `nil` if the old file does not exist or if the image dimensions do not match.
        def different?
          return nil unless old_file_exists?

          old_file, new_file = load_image_files(@old_file_name, @new_file_name)

          return not_different if old_file == new_file

          images = load_images(old_file, new_file)

          crop_images(images, @dimensions) if @dimensions

          old_img = images.first
          new_img = images.last

          if sizes_changed?(old_img, new_img)
            save_images(@annotated_new_file_name, new_img, @annotated_old_file_name, old_img)
            return true
          end

          return not_different if old_img.pixels == new_img.pixels

          @left, @top, @right, @bottom = find_diff_rectangle(old_img, new_img)

          return not_different if @top.nil?

          annotated_old_img, annotated_new_img = draw_rectangles(images, @bottom, @left, @right, @top)

          save_images(@annotated_new_file_name, annotated_new_img,
              @annotated_old_file_name, annotated_old_img)
          true
        end

        private def not_different
          clean_tmp_files(@annotated_old_file_name, @annotated_new_file_name)
          false
        end

        def old_file_exists?
          @old_file_name && File.exist?(@old_file_name)
        end

        def old_file_size
          @_old_filesize ||= old_file_exists? && File.size(@old_file_name)
        end

        def new_file_size
          File.size(@new_file_name)
        end

        def dimensions
          [@left, @top, @right, @bottom]
        end

        def size
          (@right - @left + 1) * (@bottom - @top + 1)
        end

        def max_color_distance
          return @max_color_distance if @max_color_distance
          old_file, new_file = load_image_files(@old_file_name, @new_file_name)
          return @max_color_distance = 0 if old_file == new_file

          old_image, new_image = load_images(old_file, new_file)

          pixel_pairs = old_image.pixels.zip(new_image.pixels)
          @max_color_distance = pixel_pairs.inject(0) do |max, (p1, p2)|
            d = ChunkyPNG::Color.euclidean_distance_rgba(p1, p2)
            [max, d].max
          end
        end

        private

        def save_images(new_file_name, new_img, org_file_name, org_img)
          org_img.save(org_file_name)
          new_img.save(new_file_name)
        end

        def clean_tmp_files(old_file_name, new_file_name)
          File.delete(old_file_name) if File.exist?(old_file_name)
          File.delete(new_file_name) if File.exist?(new_file_name)
        end

        def load_images(old_file, new_file)
          [ChunkyPNG::Image.from_blob(old_file), ChunkyPNG::Image.from_blob(new_file)]
        end

        def load_image_files(old_file_name, file_name)
          old_file = File.binread(old_file_name)
          new_file = File.binread(file_name)
          [old_file, new_file]
        end

        def sizes_changed?(org_image, new_image)
          return unless org_image.dimension != new_image.dimension
          change_msg = [org_image, new_image].map { |i| "#{i.width}x#{i.height}" }.join(' => ')
          puts "Image size has changed for #{@new_file_name}: #{change_msg}"
          true
        end

        private def crop_images(images, dimensions)
          images.map! do |i|
            if i.dimension.to_a == dimensions || i.width < dimensions[0] || i.height < dimensions[1]
              i
            else
              i.crop(0, 0, *dimensions)
            end
          end
        end

        private def draw_rectangles(images, bottom, left, right, top)
          images.map do |image|
            new_img = image.dup
            new_img.rect(left - 1, top - 1, right + 1, bottom + 1, ChunkyPNG::Color.rgb(255, 0, 0))
            new_img
          end
        end

        private def find_diff_rectangle(org_img, new_img)
          left, top, right, bottom = find_left_right_and_top(org_img, new_img)
          bottom = find_bottom(org_img, new_img, left, right, bottom)
          [left, top, right, bottom]
        end

        private def find_top(old_img, new_img)
          old_img.height.times do |y|
            old_img.width.times do |x|
              return [x, y, x, y] unless same_color?(old_img, new_img, x, y)
            end
          end
        end

        private def find_left_right_and_top(old_img, new_img)
          top = @top
          bottom = @bottom
          left = @left || old_img.width - 1
          right = @right || 0
          old_img.height.times do |y|
            (0...left).find do |x|
              next if same_color?(old_img, new_img, x, y)
              top ||= y
              bottom = y
              left = x
              right = x if x > right
              x
            end
            (old_img.width - 1).step(right + 1, -1).find do |x|
              unless same_color?(old_img, new_img, x, y)
                bottom = y
                right = x
              end
            end
          end
          [left, top, right, bottom]
        end

        private def find_bottom(old_img, new_img, left, right, bottom)
          if bottom
            (old_img.height - 1).step(bottom + 1, -1).find do |y|
              (left..right).find do |x|
                bottom = y unless same_color?(old_img, new_img, x, y)
              end
            end
          end
          bottom
        end

        private def same_color?(old_img, new_img, x, y)
          org_color = old_img[x, y]
          new_color = new_img[x, y]
          return true if org_color == new_color

          distance = ChunkyPNG::Color.euclidean_distance_rgba(org_color, new_color)
          @max_color_distance = distance if !@max_color_distance || distance > @max_color_distance

          @color_distance_limit && @color_distance_limit > 0 && distance <= @color_distance_limit
        end
      end
    end
  end
end
