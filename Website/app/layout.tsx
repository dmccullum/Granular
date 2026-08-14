import type { Metadata } from "next";
import "./globals.css";

const asset = (path: string) => `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}${path}`;

export const metadata: Metadata = {
  title: "Filmify — A photographic finish for still images",
  description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
  openGraph: {
    title: "Filmify — A photographic finish for still images",
    description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
    images: [{ url: asset("/app-icon-dark.png"), width: 1024, height: 1024, alt: "Filmify app icon" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Filmify — A photographic finish for still images",
    description: "A native Mac app for film tone, diffusion, halation, and light-responsive grain.",
    images: [asset("/app-icon-dark.png")],
  },
  icons: {
    icon: asset("/app-icon-dark.png"),
    shortcut: asset("/app-icon-dark.png"),
    apple: asset("/app-icon-dark.png"),
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
