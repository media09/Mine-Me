import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Keep the existing application URL prefix while moving the runtime to Workers.
  basePath: "/mineme",
  poweredByHeader: false,
  reactStrictMode: true,
};

export default nextConfig;
