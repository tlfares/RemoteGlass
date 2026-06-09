![Header](header.jpg)
# Remoteglass
Simple remote app for Orange France TV decoders, built (vibecoded) 100% in Swift.

## Features
- Local
- No login
- Liquid Glass
- Should work with all Orange decoders (Currently tested with Livebox 5's UHD Decoder)
- Customizable background with gradient or photo
- Haptic feedbacks
- ADS FREE
- Compact mode with TrackPad
- Squircle or Circular buttons

## Installation
Grab the latest .ipa in the Releases section and install it with any sideloading method (ALtStore, SideStore, Sideloadly,..). Also works completely fine inside LiveContainer.

## Usage
- Click "Detect"
- Choose your Decoder ip
- Test if it's the right one and click Confirm

## Known issues
The touch response shape has a higher corner radius of the actual remote buttons, that's an intrinsic Liquid Glass flaw from Apple for every non-circular shapes, Apple fixed that with iOS 27.
    The latest version includes two solutions for iOS 26 users.
    - Circular icons option
    - Disabling the HDR highlight and the button stretching in response to touch
