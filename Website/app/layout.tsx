import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Filmify — A photographic finish for still images",
  description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
  openGraph: {
    title: "Filmify — A photographic finish for still images",
    description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
    images: [{ url: "/app-icon-dark.png", width: 1024, height: 1024, alt: "Filmify app icon" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Filmify — A photographic finish for still images",
    description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
    images: ["/app-icon-dark.png"],
  },
  icons: {
    icon: "/app-icon-dark.png",
    shortcut: "/app-icon-dark.png",
    apple: "/app-icon-dark.png",
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
