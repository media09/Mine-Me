import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // MINE-ME is served under /mineme on the selected application hostname.
  basePath: "/mineme",
  poweredByHeader: false,
  reactStrictMode: true,
};

export default nextConfig;
