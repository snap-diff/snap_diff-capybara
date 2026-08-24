# frozen_string_literal: true

require "snap_diff/region"
require "snap_diff/reporting"

module SnapDiff
  module BrowserHelpers
    def self.resize_window_if_needed
      # The respond_to? guard this replaced existed because the legacy
      # mattr_accessor might not be installed yet; Config always has the
      # attribute, so only the value matters now.
      window_size = SnapDiff.config.window_size
      resize_to(window_size) if window_size
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

    # The one seam that knows, per selector, whether it found anything --
    # `all_visible_regions_for` is called once per selector and the caller
    # gets back one flattened list. The run-level tally is fed here (#277b)
    # rather than in AreaCalculator for exactly that reason: by the time
    # the regions are concatenated the attribution is gone.
    def self.bounds_for_css(*css_selectors)
      css_selectors.reduce([]) do |regions, selector|
        found = all_visible_regions_for(selector)
        SnapDiff::Reporting.record_selector_use(selector, matched: !found.empty?)
        regions.concat(found)
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

    # `minimum: 0` is load-bearing (issue #272). Capybara's `all` defaults to
    # `minimum: 1` and blocks in `synchronize` until the count is satisfied,
    # so every `skip_area`/`crop` selector matching nothing burned a full
    # `Capybara.default_max_wait_time` -- 5s by default, per selector, per
    # screenshot. One project measured `%w[picture img]` on an image-less
    # page at 10s per screenshot, 44% of their suite.
    #
    # Waiting is the wrong semantic here regardless of the cost: these
    # selectors describe a MASK over whatever is currently on the page. A
    # selector that matches nothing has nothing to mask, and that answer is
    # available immediately.
    def self.all_visible_regions_for(selector)
      BrowserHelpers.session.all(selector, visible: true, minimum: 0).map { |el| region_for(el) }
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
