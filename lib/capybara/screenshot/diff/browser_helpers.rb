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

      DISABLE_ANIMATIONS_SCRIPT = <<~JS
        if (!document.getElementById('csdDisableAnimationsStyle')) {
          let style = document.createElement('style');
          style.setAttribute('id', 'csdDisableAnimationsStyle');
          style.textContent = '*, *::before, *::after { animation-duration: 0s !important; animation-delay: 0s !important; transition-duration: 0s !important; transition-delay: 0s !important; }';
          document.head.appendChild(style);
        }
      JS

      def self.disable_animations
        session.execute_script(DISABLE_ANIMATIONS_SCRIPT)
      end

      DEFAULT_NORMALIZE_CSS = <<~CSS
        /* Kill animations and transitions */
        *, *::before, *::after {
          animation-duration: 0s !important;
          animation-delay: 0s !important;
          animation-iteration-count: 1 !important;
          transition-duration: 0s !important;
          transition-delay: 0s !important;
          scroll-behavior: auto !important;
        }

        /* Standardize font rendering */
        * {
          -webkit-font-smoothing: antialiased !important;
          -moz-osx-font-smoothing: grayscale !important;
          text-rendering: geometricPrecision !important;
        }

        /* Neutralize inputs and dynamic artifacts */
        * { caret-color: transparent !important; }
        input[type="number"]::-webkit-inner-spin-button,
        input[type="number"]::-webkit-outer-spin-button {
          -webkit-appearance: none !important;
        }

        /* Hide OS-specific scrollbars */
        ::-webkit-scrollbar { display: none !important; }
        * { scrollbar-width: none !important; -ms-overflow-style: none !important; }
      CSS

      def self.normalize_css(css = nil)
        css ||= DEFAULT_NORMALIZE_CSS

        session.execute_script(<<~JS, css)
          (function(cssText) {
            if (!document.getElementById('csdNormalizeStyle')) {
              let style = document.createElement('style');
              style.setAttribute('id', 'csdNormalizeStyle');
              style.textContent = cssText;
              document.head.appendChild(style);
            }
          })(arguments[0]);
        JS
      end

      def self.inject_custom_stylesheets(stylesheets)
        Array(stylesheets).each_with_index do |css, index|
          inject_stylesheet(css, "csdCustomStyle#{index}")
        end
      end

      def self.inject_custom_scripts(scripts)
        Array(scripts).each do |script|
          session.execute_script(script)
        end
      end

      def self.inject_stylesheet(css, element_id)
        session.execute_script(<<~JS, css, element_id)
          (function(cssText, styleId) {
            if (!document.getElementById(styleId)) {
              let style = document.createElement('style');
              style.setAttribute('id', styleId);
              style.textContent = cssText;
              document.head.appendChild(style);
            }
          })(arguments[0], arguments[1]);
        JS
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
        BrowserHelpers.session.all(selector, visible: true).map { |el| region_for(el) }
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

      FONTS_READY_SCRIPT = <<~JS
        (function() {
          if (!document.fonts) return true;
          return document.fonts.status === "loaded";
        })();
      JS

      def self.fonts_ready?
        BrowserHelpers.session.evaluate_script(FONTS_READY_SCRIPT)
      end

      def self.current_capybara_driver_class
        session.driver.class
      end
    end
  end
end
