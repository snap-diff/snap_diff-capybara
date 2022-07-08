# frozen_string_literal: true

class Region
  attr_accessor :x, :y, :width, :height

  def initialize(x, y, width, height)
    @x, @y, @width, @height = x, y, width, height
  end

  def self.from_top_left_corner_coordinates(x, y, width, height)
    return nil unless x && y && width && height
    return nil if width < 0 || height < 0

    Region.new(x, y, width, height)
  end

  def self.from_edge_coordinates(left, top, right, bottom)
    return nil unless left && top && right && bottom
    return nil if right < left || bottom < top

    Region.new(left, top, right - left, bottom - top)
  end

  def to_edge_coordinates
    [left, top, right, bottom]
  end

  def to_top_left_corner_coordinates
    [x, y, width, height]
  end

  def top
    y
  end

  def bottom
    y + height
  end

  def left
    x
  end

  def right
    x + width
  end

  def size
    return 0 if width < 0 || height < 0

    result = width * height
    result.zero? ? 1 : result
  end

  def to_a
    [@x, @y, @width, @height]
  end

  def find_intersect_with(region)
    return nil unless intersect?(region)

    new_left = [x, region.x].max
    new_top = [y, region.y].max

    Region.new(new_left, new_top, [right, region.right].min - new_left, [bottom, region.bottom].min - new_top)
  end

  def intersect?(region)
    left <= region.right && right >= region.left && top <= region.bottom && bottom >= region.top
  end

  def move_by(right_by, down_by)
    Region.new(x + right_by, y + down_by, width, height)
  end

  def find_relative_intersect(region)
    intersect = find_intersect_with(region)
    return nil unless intersect

    intersect.move_by(-x, -y)
  end

  def cover?(x, y)
    left <= x && x <= right && top <= y && y <= bottom
  end
end
