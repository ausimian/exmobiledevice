# Changelog

## Unreleased

### Fixes

- Handle Permission Denied error in FileConduit

## 0.2.16 - 2024-05-09

## Fixes

- Return error on ssl connection failure in `ExMobileDevice.Lockdown.start_session/1`.

## 0.2.15 - 2024-04-05

### Fixes

- Fix web session creation when Safari is already running

## 0.2.14 - 2024-04-03

### Fixes

- Fix bug in disk-signing.

## 0.2.13 - 2024-04-02

### Enhancements

- Improve error handling on disk-signing failures.

## 0.2.12 - 2024-03-06

### Enhancements

- Support for mounting developer disks on iOS16 and below.

## 0.2.11 - 2024-03-05

### Enhancements

- Support for copying and clearing crash logs

## 0.2.10 - 2024-03-01

### Fixes

- Drop unhandled (pairing) messages from usbmuxd
- Improve web-inspector state machine

## 0.2.9 - 2024-02-28

### Fixes

- More github action shenanighans

## 0.2.8 - 2024-02-28

### Fixes

- Switch to more recent action

## 0.2.7 - 2024-02-28

### Fixes

- Publish from github

## 0.2.6 - 2024-02-27

### Enhancements

- Add DDI mounting support

### Fixes

- Fix muxd framing issue

## 0.2.5 - 2024-02-22

### Fixes

- Fix controlling process handling

## 0.2.4 - 2024-02-22

### Fixes

- Fix state management in ExMobileDevice.WebInspector

## 0.2.3 - 2024-02-20

### Fixes

- Fix call to ExMobileDevice.Muxd.connect/0

## 0.2.2 - 2024-02-20

### Fixes

- Fix default configuration

## 0.2.1 - 2024-02-17

### Fixes

- Fix root page in docs

## 0.2.0 - 2024-02-17

### Enhancements

- [ExMobileDevice.WebInspector] Automate web-browsing

## 0.1.0 - 2024-02-05

### Initial revision

- [ExMobileDevice.Muxd] Device enumeration and notification of attach/detach
- [ExMobileDevice.Lockdown] Retrieval of device configuration
- [ExMobileDevice.Diagnostics] Device reboot and shutdown
- [ExMobileDevice.Syslog] Syslog streaming
