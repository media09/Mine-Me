import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "MINE-ME — Calcul communautaire",
  description:
    "Contribuez volontairement à un réseau de calcul dans votre navigateur, avec un contrôle transparent de votre appareil.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="fr">
      <body>{children}</body>
    </html>
  );
}
