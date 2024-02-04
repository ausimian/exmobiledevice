import Config

config :exmobiledevice, ExMobileDevice.Muxd,
  addr: {:local, "/var/run/usbmuxd"},
  port: 0
