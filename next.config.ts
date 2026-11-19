import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // The production site is hosted at https://app.sharedboost.com/mineme.
  basePath: "/mineme",
  output: "standalone",
  poweredByHeader: false,
  reactStrictMode: true,
};

export default nextConfig;
