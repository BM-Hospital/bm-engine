/** @type {import("next").NextConfig} */
export default {
  serverExternalPackages: ["bm-engine"],
  // the native platform package (bm-engine-<platform>) is not followed by Turbopack's file tracing
  outputFileTracingIncludes: { "/*": ["./node_modules/bm-engine-*/**"] },
};
