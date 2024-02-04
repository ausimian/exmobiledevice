# ExMobileDevice

An OTP application to talk to iPhones via `usbmuxd` on OSX and Linux.

Current functionality is minimal but includes:

- Device enumeration and notification of attach/detach
- Retrieval of device configuration
- Device reboot and shutdown
- Syslog streaming

Planned for future releases:

- WebInspector support (automate browsing sessions without SafariDriver)
- Application management (install, run)
- Device pairing

Contributions are welcome.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `exmobiledevice` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:exmobiledevice, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/exmobiledevice>.

## Acknowledgements

- Most of the heavy lifting has been done by [pymobiledevice3](https://github.com/doronz88/pymobiledevice3). Give it a star.
