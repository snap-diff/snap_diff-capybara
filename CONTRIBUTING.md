Contributing
============

Bug reports and pull requests are welcome on GitHub at https://github.com/donv/capybara-screenshot-diff.
This project is intended to be a safe, welcoming space for collaboration, and contributors are expected
to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## Testing

Run the tests before committing using Rake

    rake

## Merging to master

Before merging to `master`,
please have a member of the project review your changes,
and make sure the tests are green.

## Releasing

To release a new version, update the version number in
[lib/capybara/screenshot/diff/version.rb](lib/capybara/screenshot/diff/version.rb),
and then run

    bundle exec rake release

which will create a git tag for the version, push git commits and tags, and
push the `.gem` file to [rubygems.org](https://rubygems.org).
