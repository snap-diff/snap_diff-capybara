require 'chunky_png'

module Capybara
  module Screenshot
    module Diff
      class ImageCompare
        include ChunkyPNG::Color

        def self.compare(file_name, old_file_name, dimensions = nil)
          name = file_name.chomp('.png')
          org_file_name = "#{name}_0.png~"
          new_file_name = "#{name}_1.png~"

          return nil unless File.exist? old_file_name

          images = load_images(old_file_name, file_name)

          unless images
            clean_tmp_files(new_file_name, org_file_name)
            return false
          end

          crop_images(images, dimensions) if dimensions
          org_img = images.first
          new_img = images.last
          if sizes_changed?(org_img, new_img, name)
            save_images(new_file_name, new_img, org_file_name, org_img)
            return true
          end

          if org_img.pixels == new_img.pixels
            clean_tmp_files(new_file_name, org_file_name)
            return false
          end

          bottom, left, right, top = find_diff_rectangle(org_img, new_img)
          draw_rectangles(images, bottom, left, right, top)
          save_images(new_file_name, new_img, org_file_name, org_img)
          true
        end

        def self.save_images(new_file_name, new_img, org_file_name, org_img)
          org_img.save(org_file_name)
          new_img.save(new_file_name)
        end

        def self.clean_tmp_files(new_file_name, org_file_name)
          File.delete(org_file_name) if File.exists?(org_file_name)
          File.delete(new_file_name) if File.exists?(new_file_name)
        end

        private

        def self.load_images(old_file_name, file_name)
          old_file = File.read(old_file_name)
          new_file = File.read(file_name)

          return false if old_file == new_file

          [ChunkyPNG::Image.from_blob(old_file), ChunkyPNG::Image.from_blob(new_file)]
        end

        def self.sizes_changed?(org_image, new_image, name)
          if org_image.dimension != new_image.dimension
            puts "Image size has changed for #{name}: #{[org_image, new_image].map { |i| "#{i.width}x#{i.height}" }.join(' => ')}"
            return true
          end
        end

        def self.crop_images(images, dimensions)
          images.map! do |i|
            if i.dimension.to_a == dimensions || i.width < dimensions[0] || i.height < dimensions[1]
              i
            else
              i.crop(0, 0, *dimensions)
            end
          end
        end

        def self.draw_rectangles(images, bottom, left, right, top)
          (1..2).each do |i|
            images.each do |image|
              image.rect(left - 1, top - 1, right + 1, bottom + 1, ChunkyPNG::Color.rgb(255, 0, 0))
            end
          end
        end

        def self.find_diff_rectangle(org_img, new_img)
          top = bottom = nil
          left = org_img.width
          right = -1
          org_img.height.times do |y|
            (0...left).find do |x|
              if org_img[x, y] != new_img[x, y]
                top ||= y
                bottom = y
                left = x
                right = x if x > right
              end
            end
            (org_img.width - 1).step(right + 1, -1).find do |x|
              if org_img[x, y] != new_img[x, y]
                bottom = y
                right = x
              end
            end
          end
          (org_img.height - 1).step(bottom + 1, -1).find do |y|
            ((left + 1)..(right - 1)).find do |x|
              if org_img[x, y] != new_img[x, y]
                bottom = y
              end
            end
          end
          return bottom, left, right, top
        end
      end
    end
  end
end
