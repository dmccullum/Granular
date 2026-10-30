import type { Metadata } from "next";
import "./globals.css";

const asset = (path: string) => `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}${path}`;

// Share previews need absolute URLs; without one the image resolves against the build machine (http://localhost:3000).
const siteUrl = "https://dmccullum.github.io/Granular";

export const metadata: Metadata = {
  title: "Granular — A film finish for still images",
  description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
  openGraph: {
    title: "Granular — A film finish for still images",
    description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
    images: [{ url: `${siteUrl}/share-card.png?v=1`, width: 1200, height: 630, alt: "Granular: a film finish for still images, beside a 35mm film canister" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Granular — A film finish for still images",
    description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
    images: [`${siteUrl}/share-card.png?v=1`],
  },
  icons: {
    icon: { url: asset("/favicon.png?v=11"), type: "image/png", sizes: "64x64" },
    shortcut: asset("/favicon.png?v=11"),
    apple: { url: asset("/apple-touch-icon.png?v=11"), sizes: "180x180" },
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
