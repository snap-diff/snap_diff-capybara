# Screenshot Organization

## Taking screenshots

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

To store the screenshot history, add the `doc/screenshots` directory to your
version control system (git).

Screenshots are compared to the previously COMMITTED version of the same screenshot.

**Note:** When a screenshot differs, diff artifacts (`.diff.png`, `.heatmap.diff.png`, etc.) are generated alongside the baseline. Add `*.diff.png`, `*.base.png`, `*.diff.webp`, `*.base.webp`, and `snap_diff_report.html` to your `.gitignore`. Clean up artifacts with `rake snap_diff:clean`.

## Screenshot groups

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
      00_welcome_index
      01_feature_index
      02_action_performed
```

**Note:** `screenshot_group` sets the group name for organizing screenshots. It does not delete existing files.


## Screenshot sections

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
        00_subfeature_index
        01_action_performed
```


## Setting `screenshot_section` and/or `screenshot_group` for all tests

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


## Capturing one area instead of the whole page

You can crop images before comparison to be run, by providing region to crop as `[left, top, right, bottom]` or by css selector like `body .tag`

```ruby
test 'the cool' do
  visit '/feature'
  screenshot 'cool_element', crop: '#my_element'
end
```

**Note:** When using a retina device screenshots dimensions might be off. If
you are using (headless) chrome you can prevent this by setting the
`force-device-scale-factor` argument to `1`.

For Rails system specs using selenium you can do so for example by using the
following snippet:

```ruby
driven_by :selenium, using: :chrome_headless do |options|
  options.args << '--force-device-scale-factor=1'
end
```

## Multiple Capybara drivers

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
        00_welcome_index
        01_feature_index
        02_action_performed
    selenium
      useful_feature
        00_welcome_index
        01_feature_index
        02_action_performed
```

## Multiple OSs

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
        00_welcome_index
        01_feature_index
        02_action_performed
    windows
      useful_feature
        00_welcome_index
        01_feature_index
        02_action_performed
```

If you combine this config with the `add_driver_path` config, the driver will be
put in front of the OS name.

[← Back to README](../README.md)
