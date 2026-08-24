export type GeocodeResult = {
  lat: number;
  lon: number;
  displayName: string;
};

const GEOCODE_MARKER = "<!-- college-geocode:";
const GEOCODE_END = " -->";

export function parseGeocodeFromNotes(notes: string): {
  geocode: GeocodeResult | null;
  userNotes: string;
} {
  const start = notes.indexOf(GEOCODE_MARKER);
  if (start === -1) {
    return { geocode: null, userNotes: notes.trim() };
  }
  const end = notes.indexOf(GEOCODE_END, start);
  if (end === -1) {
    return { geocode: null, userNotes: notes.trim() };
  }
  const payload = notes.slice(start + GEOCODE_MARKER.length, end);
  const before = notes.slice(0, start).trim();
  const after = notes.slice(end + GEOCODE_END.length).trim();
  const userNotes = [before, after].filter(Boolean).join("\n");
  try {
    const parsed = JSON.parse(payload) as {
      lat?: number;
      lon?: number;
      displayName?: string;
    };
    if (
      typeof parsed.lat === "number" &&
      typeof parsed.lon === "number" &&
      typeof parsed.displayName === "string"
    ) {
      return {
        geocode: {
          lat: parsed.lat,
          lon: parsed.lon,
          displayName: parsed.displayName,
        },
        userNotes,
      };
    }
  } catch {
    /* ignore malformed marker */
  }
  return { geocode: null, userNotes: notes.trim() };
}

export function embedGeocodeInNotes(
  notes: string,
  geocode: GeocodeResult | null,
): string {
  const { userNotes } = parseGeocodeFromNotes(notes);
  if (!geocode) {
    return userNotes;
  }
  const marker = `${GEOCODE_MARKER}${JSON.stringify({
    lat: geocode.lat,
    lon: geocode.lon,
    displayName: geocode.displayName,
  })}${GEOCODE_END}`;
  return userNotes ? `${userNotes}\n${marker}` : marker;
}

export function appleMapsUrl(query: string, geocode?: GeocodeResult | null): string {
  if (geocode) {
    return `maps://?q=${geocode.lat},${geocode.lon}`;
  }
  return `maps://?q=${encodeURIComponent(query)}`;
}

export function googleMapsUrl(query: string, geocode?: GeocodeResult | null): string {
  if (geocode) {
    return `https://maps.google.com/?q=${geocode.lat},${geocode.lon}`;
  }
  return `https://maps.google.com/?q=${encodeURIComponent(query)}`;
}

export function openStreetMapUrl(query: string, geocode?: GeocodeResult | null): string {
  if (geocode) {
    return `https://www.openstreetmap.org/?mlat=${geocode.lat}&mlon=${geocode.lon}#map=16/${geocode.lat}/${geocode.lon}`;
  }
  return `https://www.openstreetmap.org/search?query=${encodeURIComponent(query)}`;
}
