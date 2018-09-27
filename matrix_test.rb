#!/usr/bin/env ruby -w

system('rubocop --auto-correct') || exit(1)

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
  puts '*' * 80
end

def use_gemfile(ruby, gemfile, update_gemfiles)
  puts '$' * 80
  puts "Testing #{gemfile}"
  puts
  ENV['BUNDLE_GEMFILE'] = gemfile
  if update_gemfiles
    system "chruby-exec #{ruby} -- bundle update"
  else
    system "chruby-exec #{ruby} -- bundle check || chruby-exec #{ruby} -- bundle install"
  end || exit(1)
  yield
  puts "Testing #{gemfile} OK"
  puts '$' * 80
end

travis['rvm'].each do |ruby|
  next if ruby =~ /head/ # ruby-install does not support HEAD installation

  puts '#' * 80
  puts "Testing #{ruby}"
  puts
  system "ruby-install --no-reinstall #{ruby}" || exit(1)
  bundler_gem_check_cmd = "chruby-exec #{ruby} -- gem query -i -n bundler >/dev/null"
  system "#{bundler_gem_check_cmd} || chruby-exec #{ruby} -- gem install bundler" || exit(1)
  travis['gemfile'].each do |gemfile|
    if travis['matrix'] &&
        (travis['matrix']['exclude'].to_a + travis['matrix']['allowed_failures'].to_a)
            .any? { |f| f['rvm'] == ruby && f['gemfile'] == gemfile }
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
