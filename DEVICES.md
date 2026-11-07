# Devices

Devices people have run Solaarchy with. Anything Solaar can see should work
([Supported hardware](README.md#supported-hardware)); this list is what someone
has actually seen working.

| Device | Connection | Battery | Backlight | LED | Reported by |
|---|---|---|---|---|---|
| G403 HERO Gaming Mouse | ? | – | – | ✅ both zones | @cbeaujoin ([#8](https://github.com/C50NK4/Solaarchy/pull/8)) |
| MX Keys | ? | ✅ | ✅ | – | @cbeaujoin ([#8](https://github.com/C50NK4/Solaarchy/pull/8)) |
| MX Keys Mini | Bluetooth | ? | ? | – | @Foufou-exe ([#6](https://github.com/C50NK4/Solaarchy/pull/6)) |
| MX Keys Mini for Business | Bolt | ✅ | ✅ | – | @C50NK4 |
| MX Master 3 | ? | ✅ | – | – | @cbeaujoin ([#8](https://github.com/C50NK4/Solaarchy/pull/8)) |
| MX Master 4 | Bolt | ✅ | – | – | @C50NK4 |
| MX Mechanical Mini | Bolt | ? | ? | – | @claytonfaria ([#3](https://github.com/C50NK4/Solaarchy/issues/3)) |

✅ works · ⚠️ works in part, see the notes · ❌ doesn't work · – the device doesn't
have it · ? not reported

## Add yours

Open a pull request that adds one row, or fills in a `?`:

1. Keep the table sorted by device name. A device on two connections gets two rows.
2. **Device:** the name `solaar show` prints.
3. **Connection:** Bolt, Unifying, Lightspeed, Nano, USB or Bluetooth.
4. **Battery, Backlight, LED:** only what you tried yourself. Put a short note
   under the table for a ⚠️ or ❌, and open an issue if it's a bug.
5. In the pull request, say which Solaarchy and Solaar versions you ran.

Leave serial numbers out: `solaar show` prints them, and this list doesn't need them.
