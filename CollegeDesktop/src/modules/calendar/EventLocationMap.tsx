import { useEffect, useRef } from "react";
import L from "leaflet";
import iconRetina from "leaflet/dist/images/marker-icon-2x.png";
import icon from "leaflet/dist/images/marker-icon.png";
import shadow from "leaflet/dist/images/marker-shadow.png";
import "leaflet/dist/leaflet.css";
import type { GeocodeResult } from "./locationGeocode";

L.Icon.Default.mergeOptions({
  iconUrl: icon,
  iconRetinaUrl: iconRetina,
  shadowUrl: shadow,
});

export function EventLocationMap({ geocode }: { geocode: GeocodeResult }) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    const map = L.map(el, {
      center: [geocode.lat, geocode.lon],
      zoom: 15,
      zoomControl: false,
      attributionControl: true,
      dragging: false,
      scrollWheelZoom: false,
      doubleClickZoom: false,
      boxZoom: false,
      keyboard: false,
    });

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    }).addTo(map);

    L.marker([geocode.lat, geocode.lon]).addTo(map);

    return () => {
      map.remove();
    };
  }, [geocode.lat, geocode.lon]);

  return <div ref={containerRef} className="h-[240px] w-full" aria-label="Map preview" />;
}
