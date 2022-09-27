[![Test](https://github.com/donv/capybara-screenshot-diff/actions/workflows/test.yml/badge.svg)](https://github.com/donv/capybara-screenshot-diff/actions/workflows/test.yml)

# Capybara::Screenshot::Diff

Ever wondered what your project looked like two years ago?  To answer that, you
start taking screen shots during your tests.  Capybara provides the
`save_screenshot` method for this.  Very good.

Ever introduced a graphical change unintended?  Never want it to happen again?
Then this gem is for you!  Use this gem to detect changes in your pages by
taking screen shots and comparing them to the previous revision.

## Installation

Add these lines to your application's Gemfile:

```ruby
gem 'capybara-screenshot-diff'
gem 'oily_png', platform: :ruby
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capybara-screenshot-diff

### Requirements

* [for :vips driver] libvips 8.9 or later, see the [libvips install instructions](https://libvips.github.io/libvips/install.html)

## Usage

### Minitest

In your test class, include the `Capybara::Screenshot::Diff` module:

```ruby
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include Capybara::Screenshot::Diff
  # ...
end
```

### RSpec

```ruby
describe 'Permissions admin', type: :feature, js: true do

  include Capybara::Screenshot::Diff

  it 'works with permissions' do
    visit('/')
    screenshot 'home_page'
  end

end
```
But it's better to include it within your *_helper.rb file so that it can used anywhere in your feature specs.
```ruby
# spec/feature_helper.rb
require 'capybara/screenshot/diff'

RSpec.configure do |config|
  config.include Capybara::Screenshot::Diff
end
```

### Taking screenshots

Add `screenshot '<my_feature>'` to your tests.  The screenshot will be saved in
the `doc/screenshots` directory.

Change your existing `save_screenshot` calls to `screenshot`

```ruby
test 'my useful feature' do
  visit '/'
  screenshot 'welcome_index'
  click_button 'Useful feature'
  screenshot 'feature_index'
  click_button 'Perform action'
  screenshot 'action_performed'
end
```

This will produce a sequence of images like this

```
doc
  screenshots
    action_performed
    feature_index
    welcome_index
```

To store the screen shot history, add the `doc/screenshots` directory to your
version control system (git, svn, etc).

    Screen shots are compared to the previously COMMITTED version of the same screen shot.

### Screenshot groups

Commonly it is useful to group screenshots around a feature, and record them as
a sequence.  To do this, add a `screenshot_group` call to the start of your
test.

```ruby
test 'my useful feature' do
  screenshot_group 'useful_feature'
  visit '/'
  screenshot 'welcome_index'
  click_button 'Useful feature'
  screenshot 'feature_index'
  click_button 'Perform action'
  screenshot 'action_performed'
end
```

This will produce a sequence of images like this

```
doc
  screenshots
    useful_feature
      00-welcome_index
      01-feature_index
      02-action_performed
```

**All files in the screenshot group directory will be deleted when
`screenshot_group` is called.**


#### Screenshot sections

You can introduce another level above the screenshot group called a
`screenshot_section`.  The section name is inserted just before the group name
in the save path.  If called in the setup of the test, all screenshots in
that test will get the same prefix:

```ruby
setup do
  screenshot_section 'my_feature'
end

test 'my subfeature' do
  screenshot_group 'subfeature'
  visit '/feature'
  click_button 'Interesting button'
  screenshot 'subfeature_index'
  click_button 'Perform action'
  screenshot 'action_performed'
end
```

This will produce a sequence of images like this

```
doc
  screenshots
    my_feature
      subfeature
        00-subfeature_index
        01-action_performed
```


#### Setting `screenshot_section` and/or `screenshot_group` for all tests

Setting the `screenshot_section` and/or `screenshot_group` for all tests can be
done in the super class setup:

```ruby
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  setup do
    screenshot_section class_name.underscore.sub(/(_feature|_system)?_test$/, '')
    screenshot_group name[5..-1]
  end
end
```

`screenshot_section` and/or `screenshot_group` can still be overridden in each
test.


### Capturing one area instead of the whole page

You can crop images before comparison to be run, by providing region to crop as `[left, top, right, bottom]` or by css selector like `body .tag`

```ruby
test 'the cool' do
  visit '/feature'
  screenshot 'cool_element', crop: '#my_element'
end
```


### Multiple Capybara drivers

Often it is useful to test your app using different browsers.  To avoid the
screenshots for different Capybara drivers to overwrite each other, set

```ruby
Capybara::Screenshot.add_driver_path = true
```

The example above will then save your screenshots like this
(for poltergeist and selenium):

```
doc
  screenshots
    poltergeist
      useful_feature
        00-welcome_index
        01-feature_index
        02-action_performed
    selenium
      useful_feature
        00-welcome_index
        01-feature_index
        02-action_performed
```

### Multiple OSs

If you run your tests on multiple operating systems, you will most likely find
the screen shots differ.  To avoid the screenshots for different OSs to
overwrite each other, set

```ruby
Capybara::Screenshot.add_os_path = true
```

The example above will then save your screenshots like this
(for Linux and Windows):

```
doc
  screenshots
    linux
      useful_feature
        00-welcome_index
        01-feature_index
        02-action_performed
    windows
      useful_feature
        00-welcome_index
        01-feature_index
        02-action_performed
```

If you combine this config with the `add_driver_path` config, the driver will be
put in front of the OS name.

### Screen size

You can specify the desired screen size using

```ruby
Capybara::Screenshot.window_size = [1024, 768]
```

This will force the screen shots to the given size, and skip taking screen shots
unless the desired window size can be achieved.

### Disabling screen shots

If you want to skip taking screen shots, set

```ruby
Capybara::Screenshot.enabled = false
```

You can of course set this by an environment variable

```ruby
Capybara::Screenshot.enabled = ENV['TAKE_SCREENSHOTS']
```

### Disabling diff

If you want to skip the assertion for change in the screen shot, set

```ruby
Capybara::Screenshot::Diff.enabled = false
```

Using an environment variable

```ruby
Capybara::Screenshot::Diff.enabled = ENV['COMPARE_SCREENSHOTS']
```

### Screen shot save path

By default, `Capybara::Screenshot::Diff` saves screenshots to a
`doc/screenshots` folder, relative to either `Rails.root` (if you're in Rails),
or your current directory otherwise.

If you want to change where screenshots are saved to, then there are two
configuration options that that are relevant.

The most likely one you'll want to modify is ...

```ruby
Capybara::Screenshot.save_path = "other/path"
```

The `save_path` option is relative to `Capybara::Screenshot.root`.

`Capybara::Screenshot.root` defaults to either `Rails.root` (if you're in
Rails) or your current directory. You can change it to something entirely
different if necessary, such as when using an alternative web framework.

```ruby
Capybara::Screenshot.root = Hanami.root
```

### Screen shot stability

To ensure that animations are finished before saving a screen shot, you can add
a stability time limit.  If the stability time limit is set, a second screen
shot will be taken and compared to the first.  This is repeated until two
subsequent screen shots are identical.

```ruby
Capybara::Screenshot.stability_time_limit = 0.1
```

This can be overridden on a single screenshot:

```ruby
test 'stability_time_limit' do
  visit '/'
  screenshot 'index', stability_time_limit: 0.5
end
```

### Maximum wait limit

When the `stability_time_limit` is set, but no stable screenshot can be taken, a timeout occurs.
The timeout occurs after `Capybara.default_max_wait_time`, but can be overridden by an option.

```ruby
test 'max wait time' do
  visit '/'
  screenshot 'index', wait: 20.seconds
end
```

### Hiding the caret for active input elements

In Chrome the screenshot includes the blinking input cursor.  This can make it impossible to get a
stable screenshot.  To get around this you can set the `hide caret` option:

```ruby
Capybara::Screenshot.hide_caret = true
```

This will make the cursor (caret) transparent (invisible), so the blinking does not delay the screen shot.


### Removing focus from the active element

Another way to avoid the cursor blinking is to set the `blur_active_element` option:

```ruby
Capybara::Screenshot.blur_active_element = true
```

This will remove the focus from the active element, removing the blinking cursor.



### Allowed color distance

Sometimes you want to allow small differences in the images.  For example, Chrome renders the same
page slightly differently sometimes.  You can set set the color difference threshold for the
comparison using the `color_distance_limit` option to the `screenshot` method:

```ruby
test 'color threshold' do
  visit '/'
  screenshot 'index', color_distance_limit: 30
end
```

The difference is calculated as the eucledian distance.  You can also set this globally:

```ruby
Capybara::Screenshot::Diff.color_distance_limit = 42
```


### Allowed shift distance

Sometimes you want to allow small movements in the images.  For example, jquer-tablesorter
renders the same table slightly differently sometimes.  You can set set the shift distance
threshold for the comparison using the `shift_distance_limit` option to the `screenshot`
method:

```ruby
test 'color threshold' do
  visit '/'
  screenshot 'index', shift_distance_limit: 2
end
```

The difference is calculated as maximum distance in either the X or the Y axis.
You can also set this globally:

```ruby
Capybara::Screenshot::Diff.shift_distance_limit = 1
```

**Note:** For each increase in `shift_distance_limit` more pixels are searched for a matching color value, and
this will impact performance **severely** if a match cannot be found.

If `shift_distance_limit` is `nil` shift distance is not measured.  If `shift_distance_limit` is set,
even to `0`, shift distance is measured and reported on image differences.

### Allowed difference size

You can set set a threshold for the differing area size for the comparison
using the `area_size_limit` option to the `screenshot` method:

```ruby
test 'area threshold' do
  visit '/'
  screenshot 'index', area_size_limit: 17
end
```

The difference is calculated as `width * height`.  You can also set this globally:

```ruby
Capybara::Screenshot::Diff.area_size_limit = 42
```


### Skipping an area

Sometimes you have expected change that you want to ignore.
You can use the `skip_area` option with `[left, top, right, bottom]`
or css selector like `'#footer'` or `'.container .skipped_element'` to the `screenshot` method to ignore an area:

```ruby
test 'unstable area' do
  visit '/'
  screenshot 'index', skip_area: [[17, 6, 27, 16], '.container .skipped_element', '#footer']
end
```

The arguments are `[left, top, right, bottom]` for the area you want to ignore.  You can also set this globally:

```ruby
Capybara::Screenshot::Diff.skip_area = [0, 0, 64, 48]
```

If you need to ignore multiple areas:

```ruby
screenshot 'index', skip_area: [[0, 0, 64, 48], [17, 6, 27, 16], 'css_selector .element']
```

### Available Image Processing Drivers

There are several image processing supported by this gem.
There are several options to setup active driver: `:auto`, `:chunky_png` and `:vips`.

* `:auto` - will try to load `:vips` if there is gem `ruby-vips`, in other cases will load `:chunky_png`
* `:chunky_png` and `:vips` will load correspondent driver

### Enable VIPS image processing

[Vips](https://www.rubydoc.info/gems/ruby-vips/Vips/Image) driver provides a faster comparison,
and could be enabled by adding `ruby-vips` to `Gemfile`.

If need to setup explicitly Vips driver, there are several ways to do this:

* Globally: `Capybara::Screenshot::Diff.driver = :vips`
* Per screenshot option: `screenshot 'index', driver: :vips`

With enabled VIPS there are new alternatives to process differences, which easier to find and support.
For example, `shift_distance_limit` is very heavy operation. Instead better to use `median_filter_window_size`. 

#### Tolerance level (vips only)

You can set a “tolerance” anywhere from 0% to 100%. This is the amount of change that's allowable.
If the screenshot has changed by more than that amount, it'll flag it as a failure.

This is alternative to "Allowed difference size", only the difference that area calculates including valid pixels.
But "tolerance" compares only different pixels.

You can use the `tolerance` option to the `screenshot` method to set level:

```ruby
test 'unstable area' do
  visit '/'
  screenshot 'index', tolerance: 0.3
end
```

You can also set this globally:

```ruby
Capybara::Screenshot::Diff.tolerance = 0.3
```

#### Median filter size (vips only)

This is an alternative to "Allowed shift distance", but much faster.
You can find more about this strategy on [Median Filter](https://en.wikipedia.org/wiki/Median_filter).
Think about this like smoothing of the image, before comparison.

You can use the `median_filter_window_size` option to the `screenshot` method to set level:

```ruby
test 'unstable area' do
  visit '/'
  screenshot 'index', median_filter_window_size: 2
end
```

### Skipping stack frames in the error output

If you would like to override the `screenshot` method or for some other reason would like to skip stack
frames when reporting image differences, you can use the `skip_stack_frames` option:

```ruby
test 'test visiting the index' do
  visit root_path
  screenshot :index
end

private

def screenshot(name, **options)
  super(name, skip_stack_frames: 1, **options)
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies.
Then, run `rake test` to run the tests.
You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

To release a new version, update the version number in `lib/capybara/screenshot/diff/version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/donv/capybara-screenshot-diff.
This project is intended to be a safe, welcoming space for collaboration,
and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

