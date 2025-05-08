# frozen_string_literal: true

require_relative "region"

module Capybara
  module Screenshot
    module BrowserHelpers
      def self.resize_window_if_needed
        if ::Capybara::Screenshot.respond_to?(:window_size) && ::Capybara::Screenshot.window_size
          resize_to(::Capybara::Screenshot.window_size)
        end
      end

      def self.resize_to(window_size)
        if session.driver.respond_to?(:resize)
          session.driver.resize(*window_size)
        elsif BrowserHelpers.selenium?
          session.driver.browser.manage.window.resize_to(*window_size)
        end
      end

      def self.selenium?
        current_capybara_driver_class <= Capybara::Selenium::Driver
      end

      def self.window_size_is_wrong?(expected_window_size = nil)
        selenium? && expected_window_size &&
          session.driver.browser.manage.window.size != ::Selenium::WebDriver::Dimension.new(*expected_window_size)
      end

      def self.bounds_for_css(*css_selectors)
        css_selectors.reduce([]) do |regions, selector|
          regions.concat(all_visible_regions_for(selector))
        end
      end

      IMAGE_WAIT_SCRIPT = <<~JS
        function pending_image() {
          const images = document.images
          for (var i = 0; i < images.length; i++) {
            if (!images[i].complete && images[i].loading !== "lazy") {
                return images[i].src
            }
          }
          return false
        }(window)
      JS

      HIDE_CARET_SCRIPT = <<~JS
        if (!document.getElementById('csdHideCaretStyle')) {
          let style = document.createElement('style');
          style.setAttribute('id', 'csdHideCaretStyle');
          document.head.appendChild(style);
          let styleSheet = style.sheet;
          styleSheet.insertRule("* { caret-color: transparent !important; }", 0);
        }
      JS

      def self.hide_caret
        session.execute_script(HIDE_CARET_SCRIPT)
      end

      FIND_ACTIVE_ELEMENT_SCRIPT = <<~JS
        function activeElement(){
          const ae = document.activeElement; 
          if (ae.nodeName === "INPUT" || ae.nodeName === "TEXTAREA") { 
            ae.blur();      
            return ae;
          }
          return null;
        }(window);
      JS

      def self.blur_from_focused_element
        session.evaluate_script(FIND_ACTIVE_ELEMENT_SCRIPT)
      end

      GET_BOUNDING_CLIENT_RECT_SCRIPT = <<~JS
        [
          this.getBoundingClientRect().left,
          this.getBoundingClientRect().top,
          this.getBoundingClientRect().right,
          this.getBoundingClientRect().bottom
        ]
      JS

      def self.all_visible_regions_for(selector)
        BrowserHelpers.session.all(selector, visible: true).map(&method(:region_for))
      end

      def self.region_for(element)
        element.evaluate_script(GET_BOUNDING_CLIENT_RECT_SCRIPT).map { |point| point.negative? ? 0 : point.ceil.to_i }
      end

      def self.session
        Capybara.current_session
      end

      def self.pending_image_to_load
        BrowserHelpers.session.evaluate_script(IMAGE_WAIT_SCRIPT)
      end

      def self.current_capybara_driver_class
        session.driver.class
      end
    end
  end
end
