import type { NextConfig } from "next";

const isGitHubPages = process.env.GITHUB_PAGES === "true";

const nextConfig: NextConfig = {
  // GitHub Pages serves the project from /Granular and only supports static files.
  ...(isGitHubPages
    ? {
        output: "export",
        assetPrefix: "/Granular",
        trailingSlash: true,
      }
    : {}),
};

export default nextConfig;
