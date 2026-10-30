import type { Metadata } from "next";
import "./globals.css";

const asset = (path: string) => `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}${path}`;

// Share previews need absolute URLs; without one the image resolves against the build machine (http://localhost:3000).
const siteUrl = "https://dmccullum.github.io/Granular";

export const metadata: Metadata = {
  title: "Granular — A photographic finish for still images",
  description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
  openGraph: {
    title: "Granular — A photographic finish for still images",
    description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
    images: [{ url: `${siteUrl}/app-icon.png?v=11`, width: 1024, height: 1024, alt: "Granular app icon" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Granular — A photographic finish for still images",
    description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
    images: [`${siteUrl}/app-icon.png?v=11`],
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
