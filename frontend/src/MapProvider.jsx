// src/MapProvider.jsx
import React from "react";
import { useJsApiLoader } from "@react-google-maps/api";

const LIBRARIES = ["places", "geometry", "marker"];

export default function MapProvider({ children }) {
  const { isLoaded, loadError } = useJsApiLoader({
    id: "gmaps-js",
    googleMapsApiKey: import.meta.env.VITE_GMAPS_KEY,
    libraries: LIBRARIES,
  });

  if (loadError) {
    console.error("Eroare la încărcarea Google Maps:", loadError);
    return <div>Eroare la încărcarea hărții.</div>;
  }

  if (!isLoaded) {
    return <div className="p-4 text-gray-500">Se încarcă harta...</div>;
  }

  return children;
}
