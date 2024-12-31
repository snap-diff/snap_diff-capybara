# frozen_string_literal: true

ENV["CAPYBARA_DRIVER"] ||= "cuprite"

SCREEN_SIZE = [800, 600]
if ENV["CAPYBARA_DRIVER"] == "selenium_chrome_headless" && Capybara::Screenshot::Os.name == "linux"
  SCREEN_SIZE[1] += 87 # Add extra space for address field etc.
end
BROWSERS = {cuprite: "chrome", selenium_headless: "firefox", selenium_chrome_headless: "chrome"}

CHROME_ARGS = {
  "allow-running-insecure-content" => nil,
  "autoplay-policy" => "user-gesture-required",
  "disable-add-to-shelf" => nil,
  "disable-background-networking" => nil,
  "disable-background-timer-throttling" => nil,
  "disable-backgrounding-occluded-windows" => nil,
  "disable-breakpad" => nil,
  "disable-checker-imaging" => nil,
  "disable-client-side-phishing-detection" => nil,
  "disable-component-extensions-with-background-pages" => nil,
  "disable-datasaver-prompt" => nil,
  "disable-default-apps" => nil,
  "disable-desktop-notifications" => nil,
  "disable-dev-shm-usage" => nil,
  "disable-domain-reliability" => nil,
  "disable-extensions" => nil,
  "disable-features" => "TranslateUI,BlinkGenPropertyTrees",
  "disable-gpu" => nil,
  "disable-hang-monitor" => nil,
  "disable-infobars" => nil,
  "disable-ipc-flooding-protection" => nil,
  "disable-notifications" => nil,
  "disable-popup-blocking" => nil,
  "disable-prompt-on-repost" => nil,
  "disable-renderer-backgrounding" => nil,
  "disable-setuid-sandbox" => nil,
  "disable-site-isolation-trials" => nil,
  "disable-sync" => nil,
  "disable-web-security" => nil,
  "enable-automation" => nil,
  "enable-features" => "NetworkService,NetworkServiceInProcess",
  "enable-logging" => "stderr",
  "force-color-profile" => "srgb",
  "force-device-scale-factor" => "1",
  "hide-scrollbars" => nil,
  "headless" => nil,
  # "headless" => "new",
  "ignore-certificate-errors" => nil,
  "js-flags" => "--random-seed=1157259157",
  "log-level" => "0",
  "metrics-recording-only" => nil,
  "mute-audio" => nil,
  "no-default-browser-check" => nil,
  "no-first-run" => nil,
  "no-sandbox" => nil,
  "password-store=basic" => nil,
  "test-type" => nil,
  "use-mock-keychain" => nil,
  "window-size" => SCREEN_SIZE.join(",")
}

if ENV["CAPYBARA_DRIVER"] == "cuprite"
  # NOTE: do not require cuprite by default
  require "capybara/cuprite"

  Capybara.register_driver(:cuprite) do |app|
    Capybara::Cuprite::Driver.new(
      app,
      browser_options: CHROME_ARGS,
      js_errors: true,
      process_timeout: ENV["CI"] ? 40 : 5,
      screen_size: SCREEN_SIZE,
      timeout: ENV["CI"] ? 40 : 5,
      window_size: SCREEN_SIZE
    )
  end
end

Capybara.register_driver :selenium_chrome_headless do |app|
  version = Capybara::Selenium::Driver.load_selenium
  options_key = Capybara::Selenium::Driver::CAPS_VERSION.satisfied_by?(version) ? :capabilities : :options
  browser_options = Selenium::WebDriver::Chrome::Options.new
  CHROME_ARGS.each { browser_options.add_argument("--#{_1}=#{_2}") }
  Capybara::Selenium::Driver.new(app, :browser => :chrome, options_key => browser_options).tap do |driver|
    driver.browser.manage.window.size = Selenium::WebDriver::Dimension.new(*SCREEN_SIZE)
  end
end

Capybara.save_path = Pathname.new("tmp/capybara").expand_path
Capybara.javascript_driver = ENV.fetch("CAPYBARA_DRIVER", :cuprite).to_sym
Capybara.disable_animation = true
