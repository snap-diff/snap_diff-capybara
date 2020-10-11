#!/usr/bin/env ruby -w
# frozen_string_literal: true

update_gemfiles = ARGV.delete('--update')

require 'yaml'
travis = YAML.safe_load(File.read('.travis.yml'))

def run_script(ruby, env, gemfile)
  env.scan(/\b(?<key>[A-Z_]+)="(?<value>.+?)"/) do |key, value|
    ENV[key] = value
  end
  puts '*' * 80
  puts "Testing #{ruby} #{gemfile} #{env}"
  puts
  system("chruby-exec #{ruby} -- bundle exec rake") || exit(1)
  puts "Testing #{ruby} #{gemfile} OK"
  puts '*' * 80
end

def use_gemfile(ruby, gemfile, update_gemfiles)
  puts '$' * 80
  ENV['BUNDLE_GEMFILE'] = gemfile

  bundler_version = `grep -A1 "BUNDLED WITH" #{gemfile}.lock | tail -n 1`
  bundler_version = '~> 2.0' if bundler_version.strip.empty?

  version_arg = "-v '#{bundler_version}'"
  bundler_gem_check_cmd = "chruby-exec #{ruby} -- gem query -i -n bundler #{version_arg} >/dev/null"
  system "#{bundler_gem_check_cmd} || chruby-exec #{ruby} -- gem install #{version_arg} bundler" || exit(1)

  if update_gemfiles
    system "chruby-exec #{ruby} -- bundle update"
  else
    system "chruby-exec #{ruby} -- bundle check >/dev/null || chruby-exec #{ruby} -- bundle install"
  end || exit(1)
  yield
  puts '$' * 80
end

travis['rvm'].each do |ruby|
  next if /head/.match?(ruby) # ruby-install does not support HEAD installation

  puts '#' * 80
  puts "Testing #{ruby}"
  puts
  system "ruby-install --no-reinstall #{ruby}" || exit(1)
  travis['gemfile'].each do |gemfile|
    if travis['matrix'] &&
        (travis['matrix']['exclude'].to_a + travis['matrix']['allow_failures'].to_a)
            .any? { |f| f['rvm'] == ruby && (f['gemfile'].nil? || f['gemfile'] == gemfile) }
      puts 'Skipping known failure.'
      next
    end
    use_gemfile(ruby, gemfile, update_gemfiles) do
      travis['env'].each do |env|
        run_script(ruby, env, gemfile)
      end
    end
  end
  puts "Testing #{ruby} OK"
  puts '#' * 80
end

print "\033[0;32m"
print '                        TESTS PASSED OK!'
puts "\033[0m"
