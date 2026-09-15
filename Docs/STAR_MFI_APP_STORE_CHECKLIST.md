# Star MFi / App Store checklist — Alpha Pos

## Registered application identity

- App Store name: `Alpha Pos`
- Version: `1.0`
- Bundle identifier: `AltifaDev.AlphaPos`
- Registered printer: `TSP100IIIU` (`TSP143IIIU` family)
- MFi Product Plan ID (PPID): `121976-0033`
- External Accessory protocol: `jp.star-m.starpro`
- SDK: StarXpand SDK for iOS / StarIO10 `2.12.1`

## Current MFi status

- [x] Star application registration accepted.
- [x] Star confirmed it will submit the application information to Apple.
- [x] Apple MFi review completed.
- [x] Star supplied MFi Product Plan ID `121976-0033` for `TSP100IIIU`.
- [ ] PPID entered in App Store Connect **App Review Information > Notes**.

The external MFi approval gate is complete. The USB-enabled build may be sent
for App Store review after the remaining build, archive, and physical-device
checks below are complete.

## Build verification

- [x] `UISupportedExternalAccessoryProtocols` contains only
  `jp.star-m.starpro`.
- [x] StarIO10 is linked into the application target.
- [x] StarIO10 privacy manifest is embedded in the Release application.
- [x] Release device build succeeds.
- [x] Bundle identifier matches the Star registration.
- [x] Marketing version matches the Star registration.
- [ ] App Store Connect product name is exactly `Alpha Pos`.
- [ ] TSP100IIIU/TSP143IIIU firmware is version 1.7 or later.

## Physical-device acceptance test

Run on the signed Release/TestFlight-equivalent build and retain screenshots or
logs for every result.

- [ ] StarIO10 USB discovery shows the connected printer.
- [ ] Test receipt prints Thai and English text, logo, QR code, feed, and cut.
- [ ] Kitchen ticket prints correctly.
- [ ] Cash drawer opens when configured.
- [ ] Paper-empty is reported as a failure and the job is not marked successful.
- [ ] Cover-open is reported as a failure and the job is not marked successful.
- [ ] Disconnect/reconnect recovers without restarting the app.
- [ ] Ten consecutive receipts print exactly once and in order.
- [ ] App relaunch discovers and prints to the USB printer again.

## App Store submission

- [ ] Archive is signed with the App Store distribution profile.
- [ ] Validate the archive in Xcode Organizer.
- [ ] Confirm the uploaded build retains `jp.star-m.starpro` in its Info.plist.
- [ ] Add `MFi PPID: 121976-0033` to App Review Notes.
- [ ] State that the supported accessory is Star Micronics TSP100IIIU and give
  the reviewer concise connection/test instructions.
- [ ] Keep Star's acceptance email and PPID email with the release records.

## App Review Notes — ready to paste

```text
MFi Product Plan ID (PPID): 121976-0033

Alpha Pos supports the Star Micronics TSP100IIIU receipt printer connected to
an iPad by USB. Printing is implemented with the official StarXpand SDK for iOS
(StarIO10) and the registered external accessory protocol jp.star-m.starpro.

To test USB printing:
1. Connect and power on a Star Micronics TSP100IIIU printer by USB.
2. Open Alpha Pos > Settings > Printer.
3. Add or select a Star Micronics printer and choose USB Direct.
4. Run Test Print.

The application name is Alpha Pos, version 1.0, bundle identifier
AltifaDev.AlphaPos.
```
