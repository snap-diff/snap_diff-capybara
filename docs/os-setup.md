# OS Setup for Consistent Screenshots

Screenshot rendering varies across OS and C libraries. For reliable baselines
across Ubuntu (glibc) and Alpine (musl), standardize fonts and disable hinting.

## Ubuntu (glibc)

Install fonts:

```bash
sudo apt-get update
sudo apt-get install -y \
  fonts-dejavu \
  fonts-liberation \
  fonts-ubuntu \
  fonts-noto-color-emoji
```

Disable font hinting and subpixel tweaks:

```bash
sudo tee /etc/fonts/local.conf >/dev/null <<'XML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="font">
    <edit name="hinting" mode="assign"><bool>false</bool></edit>
    <edit name="autohint" mode="assign"><bool>false</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintnone</const></edit>
    <edit name="rgba" mode="assign"><const>none</const></edit>
  </match>
</fontconfig>
XML

sudo fc-cache -f
```

## Alpine (musl)

Install fonts:

```bash
apk add --no-cache \
  ttf-dejavu \
  ttf-liberation \
  ttf-ubuntu-font-family \
  font-noto-emoji
```

Disable font hinting and subpixel tweaks:

```bash
cat > /etc/fonts/local.conf <<'XML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="font">
    <edit name="hinting" mode="assign"><bool>false</bool></edit>
    <edit name="autohint" mode="assign"><bool>false</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintnone</const></edit>
    <edit name="rgba" mode="assign"><const>none</const></edit>
  </match>
</fontconfig>
XML

fc-cache -f
```

## GitHub Actions (Ubuntu)

If you use the provided setup action, the OS preparation is handled for you.
See `docs/ci-integration.md` for the GitHub Actions snippets.
