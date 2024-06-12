# ExMobileDevice

An OTP application to talk to iPhones via `usbmuxd` on OSX and Linux.

Current functionality is minimal but includes:

- Device enumeration and notification of attach/detach (`ExMobileDevice.Muxd`)
- Retrieval of device configuration (`ExMobileDevice.Lockdown`)
- Device reboot and shutdown (`ExMobileDevice.Diagnostics`)
- Syslog streaming (`ExMobileDevice.Syslog`)
- WebInspector support - automate browsing sessions without SafariDriver -
  (`ExMobileDevice.WebInspector`)
- Crash log copying and removal - (`ExMobileDevice.CrashReporter`)
- Developer Disk mounting - (`ExMobileDevice.ImageMounter`)

Planned for future releases:

- Application management (install, run)
- Device pairing

Contributions are welcome.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `exmobiledevice` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:exmobiledevice, "~> 0.2.17"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/exmobiledevice>.

## Acknowledgements

- Most of the heavy lifting has been done by [pymobiledevice3](https://github.com/doronz88/pymobiledevice3). Give it a star.
