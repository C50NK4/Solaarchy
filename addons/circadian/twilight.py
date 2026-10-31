#!/usr/bin/env python3
"""Circadian (a Solaarchy add-on): is it dark now, by civil twilight, and when
does that change?

  twilight.py OFFSET_MIN [LOCATION]

LOCATION is "lat, lon" in decimal degrees (north and east positive). Without
it, the location set for Omarchy's weather is used when it has coordinates
(~/.local/state/omarchy/settings/weather.json), else the system timezone's
reference city from zone1970.tab. No network and no location service is
involved. OFFSET_MIN widens the dark hours on both ends: 30 turns the light on
30 minutes before civil dusk and off 30 minutes after civil dawn; negative
narrows them.

Prints one JSON line:
  {"dark": true, "until": 1793430000, "dusk": "17:13", "dawn": "06:18",
   "outsideDark": true, "outsideUntil": 1793431800,
   "lat": 48.22, "lon": 16.33, "source": "timezone", "place": "Europe/Vienna"}
"dark"/"until" are the keyboard light's state and next switch, offset
included; "dusk"/"dawn" are today's local switch times, null when the sun
never crosses -6 degrees today. "outsideDark"/"outsideUntil" are the same
without the offset: what the sky does. "darkToday" lists today's dark spans
as [start, end] local clock minutes, 0..1440, offset included, for drawing.
"source" is "custom", "omarchy" or "timezone"; "place" names it.
On failure: {"error": "..."}.

--test runs the self-check.
"""

import json
import math
import os
import re
import sys
import time
from datetime import date, datetime, timedelta, timezone

ZENITH = 96.0  # civil twilight: the sun 6 degrees below the horizon
ZONE_TAB = "/usr/share/zoneinfo/zone1970.tab"
WEATHER = os.path.expanduser("~/.local/state/omarchy/settings/weather.json")


def civil_twilight(day, lat, lon):
    """(dawn, dusk) as UTC datetimes for this date, or "dark"/"light" all day.

    NOAA's general solar position equations; good to about a minute.
    """
    g = 2 * math.pi / 365 * (day.timetuple().tm_yday - 1)
    eqtime = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g)
                       - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
    decl = (0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g)
            - 0.006758 * math.cos(2 * g) + 0.000907 * math.sin(2 * g)
            - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g))
    phi = math.radians(lat)
    cos_ha = (math.cos(math.radians(ZENITH)) / (math.cos(phi) * math.cos(decl))
              - math.tan(phi) * math.tan(decl))
    if cos_ha > 1:
        return "dark"  # the sun never climbs above -6 degrees: polar night
    if cos_ha < -1:
        return "light"  # never sinks below -6 degrees: white night
    ha = math.degrees(math.acos(cos_ha))
    midnight = datetime(day.year, day.month, day.day, tzinfo=timezone.utc)
    dawn = midnight + timedelta(minutes=720 - 4 * (lon + ha) - eqtime)
    dusk = midnight + timedelta(minutes=720 - 4 * (lon - ha) - eqtime)
    return dawn, dusk


def light_spans(now, lat, lon, offset):
    """Merged light intervals around now, and today's (dawn, dusk) or None.

    Light is each day's [dawn + offset, dusk - offset]. Intervals are merged,
    so an offset larger than a short night (or day) removes it rather than
    flipping the schedule around.
    """
    pad = timedelta(minutes=offset)
    light, today = [], None
    base = now.astimezone().date()  # the local date: near midnight the UTC one is a day off
    for i in range(-2, 4):
        day = base + timedelta(days=i)
        t = civil_twilight(day, lat, lon)
        if t == "light":
            midnight = datetime(day.year, day.month, day.day, tzinfo=timezone.utc)
            span = midnight, midnight + timedelta(days=1)
        elif t == "dark":
            continue
        else:
            span = t[0] + pad, t[1] - pad
            if i == 0 and span[0] < span[1]:
                today = span
        if span[0] < span[1]:
            light.append(span)
    merged = []
    for a, b in sorted(light):
        if merged and a <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], b)
        else:
            merged.append([a, b])
    return merged, today


def schedule(now, lat, lon, offset):
    """(dark now, next change as a UTC datetime, today's (dawn, dusk) or None)."""
    merged, today = light_spans(now, lat, lon, offset)
    for a, b in merged:
        if a <= now < b:
            return False, b, today
        if a > now:
            return True, a, today
    return True, None, today


def dark_today(now, lat, lon, offset):
    """Today's dark spans as [start, end] local clock minutes, 0..1440.

    Clock minutes, not elapsed ones, so a 23- or 25-hour DST day still maps
    onto a 24-hour strip the way its times read.
    """
    merged, _ = light_spans(now, lat, lon, offset)
    d = now.astimezone().date()
    start = datetime(d.year, d.month, d.day).astimezone()
    end = (datetime(d.year, d.month, d.day) + timedelta(days=1)).astimezone()

    def minute(t):
        if t >= end:
            return 1440
        t = t.astimezone()
        return t.hour * 60 + t.minute

    spans, cursor = [], start
    for a, b in merged:
        if b <= cursor or a >= end:
            continue
        if a > cursor:
            spans.append([minute(cursor), minute(a)])
        cursor = b
    if cursor < end:
        spans.append([minute(cursor), 1440])
    return [s for s in spans if s[1] > s[0]]


def zone_location():
    """(lat, lon, zone name) of the system timezone's reference city."""
    zone = os.environ.get("TZ", "").lstrip(":")
    if not zone:
        zone = os.path.realpath("/etc/localtime").split("zoneinfo/", 1)[-1]
    with open(ZONE_TAB) as f:
        for line in f:
            fields = line.split("\t")
            if len(fields) >= 3 and fields[2].strip() == zone:
                m = re.fullmatch(r"([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?", fields[1])
                if m:
                    def deg(sign, d, mi, s):
                        v = int(d) + int(mi) / 60 + int(s or 0) / 3600
                        return -v if sign == "-" else v
                    return deg(*m.group(1, 2, 3, 4)), deg(*m.group(5, 6, 7, 8)), zone
    raise ValueError(f"no location for timezone {zone or 'UTC'}; set one as \"lat, lon\"")


def omarchy_location(path=WEATHER):
    """(lat, lon, name) set for Omarchy's weather (omarchy-weather-location), or None."""
    try:
        with open(path) as f:
            doc = json.load(f)
        lat, lon = float(doc["latitude"]), float(doc["longitude"])
    except (OSError, ValueError, KeyError, TypeError):
        return None
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None
    return lat, lon, str(doc.get("name") or "")


def parse_location(text):
    m = re.fullmatch(r"\s*([+-]?\d+(?:\.\d+)?)\s*[,;\s]\s*([+-]?\d+(?:\.\d+)?)\s*", text)
    if not m:
        raise ValueError(f"location \"{text}\" is not \"lat, lon\"")
    lat, lon = float(m.group(1)), float(m.group(2))
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError(f"location \"{text}\" is out of range")
    return lat, lon


def main(argv):
    offset = max(-120, min(120, int(argv[1]))) if len(argv) > 1 and argv[1].lstrip("-").isdigit() else 0
    location = argv[2].strip() if len(argv) > 2 else ""
    omarchy = None if location else omarchy_location()
    if location:
        (lat, lon), source, place = parse_location(location), "custom", ""
    elif omarchy:
        lat, lon, place = omarchy
        source = "omarchy"
    else:
        lat, lon, place = zone_location()
        source = "timezone"
    now = datetime.now(timezone.utc)
    dark, until, today = schedule(now, lat, lon, offset)
    outside_dark, outside_until, _ = schedule(now, lat, lon, 0)

    def local(t):
        return t.astimezone().strftime("%H:%M") if t else None

    return {"dark": dark, "until": int(until.timestamp()) if until else None,
            "dawn": local(today and today[0]), "dusk": local(today and today[1]),
            "darkToday": dark_today(now, lat, lon, offset),
            "outsideDark": outside_dark,
            "outsideUntil": int(outside_until.timestamp()) if outside_until else None,
            "lat": round(lat, 2), "lon": round(lon, 2), "source": source, "place": place}


def test():
    os.environ["TZ"] = "Europe/Vienna"  # the local-day cases below are Vienna days
    time.tzset()
    vienna = 48.2167, 16.3333
    # Vienna 2026-06-21 per sunrise-sunset.org: civil dawn 02:12:28, dusk 19:40:29 UTC.
    dawn, dusk = civil_twilight(date(2026, 6, 21), *vienna)
    assert abs((dawn - datetime(2026, 6, 21, 2, 12, 28, tzinfo=timezone.utc)).total_seconds()) < 180, dawn
    assert abs((dusk - datetime(2026, 6, 21, 19, 40, 29, tzinfo=timezone.utc)).total_seconds()) < 180, dusk
    # Longyearbyen (78.2 N): civil polar night in December, white nights in June.
    assert civil_twilight(date(2026, 12, 21), 78.22, 15.65) == "dark"
    assert civil_twilight(date(2026, 6, 21), 78.22, 15.65) == "light"
    noon = datetime(2026, 10, 31, 11, 0, tzinfo=timezone.utc)
    dark, until, (dawn, dusk) = schedule(noon, *vienna, 0)
    assert not dark and until == dusk, (dark, until, dusk)
    # The offset moves both ends outwards.
    _, _, (dawn30, dusk30) = schedule(noon, *vienna, 30)
    assert dawn30 - dawn == timedelta(minutes=30) and dusk - dusk30 == timedelta(minutes=30)
    dark, until, _ = schedule(datetime(2026, 10, 31, 23, 0, tzinfo=timezone.utc), *vienna, 0)
    assert dark and until.date() == date(2026, 11, 1) and until.hour < 7, until
    dark, until, _ = schedule(datetime(2026, 12, 21, 12, 0, tzinfo=timezone.utc), 78.22, 15.65, 0)
    assert dark and until is None
    # Big offsets at high latitude: the short night or day disappears, it never flips.
    helsinki_midnight = datetime(2026, 6, 20, 21, 0, tzinfo=timezone.utc)
    assert schedule(helsinki_midnight, 60.17, 24.94, -120)[0] is False
    # Tromso in December, +120: a short civil day shrinks to a sliver, not to 22 hours of light.
    dark, until, _ = schedule(datetime(2026, 12, 21, 9, 0, tzinfo=timezone.utc), 69.65, 18.96, 120)
    light, back = schedule(until, 69.65, 18.96, 120)[:2]
    assert dark and not light and back - until < timedelta(hours=3), (until, back)
    assert schedule(datetime(2026, 12, 21, 12, 0, tzinfo=timezone.utc), 70.98, 25.97, 120)[0]  # North Cape: none left
    # 00:30 local is still 23:30 UTC the day before: today is the local day.
    _, _, (dawn, _) = schedule(datetime(2026, 10, 31, 23, 30, tzinfo=timezone.utc), *vienna, 0)
    assert dawn.astimezone().date() == date(2026, 11, 1), dawn
    # The strip: dark from midnight to dawn and from dusk to midnight, in clock minutes.
    spans = dark_today(noon, *vienna, 0)
    _, _, (dawn, dusk) = schedule(noon, *vienna, 0)
    clock = lambda t: t.astimezone().hour * 60 + t.astimezone().minute
    assert spans == [[0, clock(dawn)], [clock(dusk), 1440]], spans
    # DST day (2026-03-29, 23 hours): still two spans on a 0..1440 clock, dawn after 05:00 CEST.
    spans = dark_today(datetime(2026, 3, 29, 12, 0, tzinfo=timezone.utc), *vienna, 0)
    assert len(spans) == 2 and spans[0][0] == 0 and spans[1][1] == 1440, spans
    assert 300 < spans[0][1] < 420 and 1140 < spans[1][0] < 1260, spans
    assert dark_today(datetime(2026, 12, 21, 12, 0, tzinfo=timezone.utc), 78.22, 15.65, 0) == [[0, 1440]]
    assert dark_today(datetime(2026, 6, 21, 12, 0, tzinfo=timezone.utc), 78.22, 15.65, 0) == []
    assert parse_location("48.21, 16.37") == (48.21, 16.37)
    assert parse_location("-33.9 151.2") == (-33.9, 151.2)
    # Omarchy's weather location: used only with coordinates.
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "weather.json")
        assert omarchy_location(path) is None
        with open(path, "w") as f:
            json.dump({"name": "Graz", "latitude": 47.07, "longitude": 15.44}, f)
        assert omarchy_location(path) == (47.07, 15.44, "Graz")
        with open(path, "w") as f:
            json.dump({"name": "Malibu"}, f)
        assert omarchy_location(path) is None
    print("ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--test"]:
        test()
        sys.exit(0)
    try:
        print(json.dumps(main(sys.argv)))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
