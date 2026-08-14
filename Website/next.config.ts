import type { NextConfig } from "next";

const isGitHubPages = process.env.GITHUB_PAGES === "true";

const nextConfig: NextConfig = {
  // GitHub Pages serves the project from /Filmify and only supports static files.
  ...(isGitHubPages
    ? {
        output: "export",
        assetPrefix: "/Filmify",
        trailingSlash: true,
      }
    : {}),
};

export default nextConfig;
