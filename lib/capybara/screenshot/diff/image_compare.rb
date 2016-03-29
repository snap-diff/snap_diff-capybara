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
          images = [
            ChunkyPNG::Image.from_file(old_file_name),
            ChunkyPNG::Image.from_file(file_name)
          ]

          if dimensions
            images.map! { |i| i.dimension.to_a == dimensions ? i : i.crop(0, 0, *dimensions) }
          end

          sizes = images.map(&:width).uniq + images.map(&:height).uniq
          if sizes.size != 2
            puts "Image size has changed for #{name}: #{images.map { |i| "#{i.width}x#{i.height}" }.join(' => ')}"
            return true
          end

          diff = []
          images.first.height.times do |y|
            images.first.row(y).each_with_index do |pixel, x|
              diff << [x, y] unless pixel == images.last[x, y]
            end
          end

          if diff.empty?
            File.delete(org_file_name) if File.exist?(org_file_name)
            File.delete(new_file_name) if File.exist?(new_file_name)
            return false
          end

          x = diff.map { |xy| xy[0] }
          y = diff.map { |xy| xy[1] }
          (1..2).each do |i|
            images.each do |image|
              image.rect(x.min - i, y.min - i, x.max + i, y.max + i, ChunkyPNG::Color.rgb(255, 0, 0))
            end
          end
          images.first.save(org_file_name)
          images.last.save(new_file_name)
          true
        end
      end
    end
  end
end
