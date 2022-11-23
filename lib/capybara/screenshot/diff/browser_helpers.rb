# frozen_string_literal: true

require_relative "region"

module Capybara
  module Screenshot
    module BrowserHelpers
      def selenium?
        current_capybara_driver_class <= Capybara::Selenium::Driver
      end

      def window_size_is_wrong?
        selenium? &&
          Screenshot.window_size &&
          page.driver.browser.manage.window.size != ::Selenium::WebDriver::Dimension.new(*Screenshot.window_size)
      end

      def rect_for(css_selector)
        all_visible_regions_for(css_selector).first
      end

      def bounds_for_css(*css_selectors)
        css_selectors.reduce([]) do |regions, selector|
          regions.concat(all_visible_regions_for(selector))
        end
      end

      IMAGE_WAIT_SCRIPT = <<~JS
        function pending_image() {
          var images = document.images;
          for (var i = 0; i < images.length; i++) {
            if (!images[i].complete) {
                return images[i].src;
            }
          }
          return false;
        }()
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

      def hide_caret
        execute_script(HIDE_CARET_SCRIPT)
      end

      FIND_ACTIVE_ELEMENT_SCRIPT = <<~JS
        function activeElement(){
          const ae = document.activeElement; 
          if (ae.nodeName === "INPUT" || ae.nodeName === "TEXTAREA") { 
            ae.blur();      
            return ae;
          }
          return null;
        }();
      JS

      def blur_from_focused_element
        page.evaluate_script(FIND_ACTIVE_ELEMENT_SCRIPT)
      end

      GET_BOUNDING_CLIENT_RECT_SCRIPT = <<~JS
        [
          this.getBoundingClientRect().left,
          this.getBoundingClientRect().top,
          this.getBoundingClientRect().right,
          this.getBoundingClientRect().bottom
        ]
      JS

      def all_visible_regions_for(selector)
        all(selector, visible: true).map(&method(:region_for))
      end

      def region_for(element)
        element.evaluate_script(GET_BOUNDING_CLIENT_RECT_SCRIPT).map { |point| point.negative? ? 0 : point.to_i }
      end

      private

      def create_output_directory_for(file_name)
        FileUtils.mkdir_p File.dirname(file_name)
      end

      private

      def pending_image_to_load
        evaluate_script IMAGE_WAIT_SCRIPT
      end

      def current_capybara_driver_class
        Capybara.current_session.driver.class
      end
    end
  end
end
