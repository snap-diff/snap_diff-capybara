# frozen_string_literal: true

require "support/setup_rails_app"
require "capybara"
require "puma"

# JRuby joins every live thread at interpreter teardown (`Ruby.tearDown` ->
# `ThreadService.teardown` -> `Thread#join`) where MRI simply kills them.
# Puma's reactor thread parks in a native kqueue/epoll poll that no
# interrupt can wake, so a Capybara-booted Puma keeps the process alive
# forever after an otherwise green run -- issue #244. Capybara's stock
# `:puma` block builds its `Puma::Server` in a block-local and joins it,
# leaving nothing anyone could stop; this equivalent block keeps the handle
# so the suite can shut the server down for real.
module StoppablePuma
  BOOTED = []

  def self.stop_all
    BOOTED.each { |server| server.stop(true) }
    BOOTED.clear
  end
end

Capybara.register_server :stoppable_puma do |app, port, host, **options|
  options = {min_threads: 0, max_threads: 4, log_writer: Puma::LogWriter.strings}.merge(options)
  Puma::Server.new(app, nil, options).tap do |server|
    server.add_tcp_listener(host, port)
    StoppablePuma::BOOTED << server
  end.run.join
end

Capybara.app = Rails.application
Capybara.default_max_wait_time = 1
Capybara.disable_animation = true
Capybara.server = :stoppable_puma
Capybara.threadsafe = true

# `minitest/autorun` owns this process's exit through its own `at_exit`,
# registered before this file loads -- a plain `at_exit` here would run
# BEFORE the suite does. The RSpec fixtures that load this file run
# standalone without minitest and need the plain hook.
if defined?(Minitest.after_run)
  Minitest.after_run { StoppablePuma.stop_all }
else
  at_exit { StoppablePuma.stop_all }
end
